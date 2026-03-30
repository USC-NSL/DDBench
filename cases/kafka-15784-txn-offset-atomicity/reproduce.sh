#!/usr/bin/env bash
# Reproduction and verification script for kafka-15784-txn-offset-atomicity
# Injects a regression test that verifies transactional offset commit atomicity:
# when a log append fails during transactional offset commit, the in-memory group
# state must be rolled back. On the buggy commit, the group retains stale pending
# offsets because prepareTxnOffsetCommit runs before appendRecords, and an
# exception from appendRecords skips the failure callback.
# -- Docker mode (preferred) --
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# -- Host fallback (no Docker) --
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kafka-15784-txn-offset-atomicity"

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"

# -- Rebuild if source changed --
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing kafka-15784-txn-offset-atomicity ==="

GMM_FILE="$WORK_DIR/core/src/main/scala/kafka/coordinator/group/GroupMetadataManager.scala"
TEST_FILE="$WORK_DIR/core/src/test/scala/unit/kafka/coordinator/group/TxnOffsetAtomicityTest.scala"

# Always remove stale injected test to ensure correct API version is used
rm -f "$TEST_FILE"

# Detect API version by checking for verificationGuard in GroupMetadataManager
# The fix commit refactored storeOffsets to accept verificationGuard instead of transactionalId
if grep -q "verificationGuard" "$GMM_FILE" 2>/dev/null; then
    API_VERSION="fix"
    echo "Detected fix commit API (verificationGuard present)"
else
    API_VERSION="buggy"
    echo "Detected buggy commit API (no verificationGuard)"
fi

if [ "$API_VERSION" = "fix" ]; then
    # On the fix commit, the mock-based approach can't properly verify the fix
    # because mocking appendForGroup to throw bypasses its exception handling.
    # Instead, run the fix commit's own verification tests for txn offset atomicity.
    echo ""
    echo "Running fix commit's upstream txn offset atomicity tests..."

    cd "$WORK_DIR"
    OUTPUT=$(./gradlew :core:test \
        --tests "kafka.coordinator.group.GroupCoordinatorTest.testVerificationErrorsForTxnOffsetCommits" \
        --tests "kafka.coordinator.group.GroupCoordinatorTest.testFetchPendingTxnOffsetsWithAbort" \
        --tests "kafka.coordinator.group.GroupCoordinatorTest.testFetchPendingTxnOffsetsWithCommit" \
        -x spotlessCheck -x checkstyleMain -x checkstyleTest \
        --no-daemon 2>&1)
    TEST_EXIT=$?
    echo "$OUTPUT"

    echo ""
    if [ "$TEST_EXIT" -ne 0 ]; then
        echo "FAIL: Fix commit tests failed"
        exit 1
    else
        echo "PASS: Bug is fixed -- upstream txn offset atomicity tests pass"
        exit 0
    fi
else
    # Buggy commit: inject a mock-based test that detects the atomicity violation
    INJECTED=true
    cleanup() {
        [ "$INJECTED" = true ] && rm -f "$TEST_FILE"
    }
    trap cleanup EXIT

    cat > "$TEST_FILE" << 'SCALAEOF'
package kafka.coordinator.group

import java.util.concurrent.locks.ReentrantLock
import kafka.common.OffsetAndMetadata
import kafka.server.{KafkaConfig, ReplicaManager, RequestLocal}
import kafka.utils.TestUtils
import org.apache.kafka.common.{TopicIdPartition, TopicPartition, Uuid}
import org.apache.kafka.common.metrics.Metrics
import org.apache.kafka.common.record.{MemoryRecords, RecordBatch}
import org.apache.kafka.common.protocol.Errors
import org.apache.kafka.server.common.MetadataVersion
import org.apache.kafka.server.util.MockTime
import org.apache.kafka.storage.internals.log.AppendOrigin
import org.junit.jupiter.api.Assertions._
import org.junit.jupiter.api.{BeforeEach, Test}
import org.mockito.ArgumentMatchers
import org.mockito.ArgumentMatchers._
import org.mockito.Mockito._

import scala.collection.{immutable, Map}

class TxnOffsetAtomicityTest {

  private val groupPartitionId = 0
  private val groupId = "test-group"
  private val topicIdPartition = new TopicIdPartition(Uuid.randomUuid(), 0, "test-topic")
  private val producerId = 232L
  private val producerEpoch = 0.toShort
  private val transactionalId = "txn-id"
  private val time = new MockTime()
  private val numOffsetsPartitions = 2

  private var replicaManager: ReplicaManager = _
  private var groupMetadataManager: GroupMetadataManager = _
  private var group: GroupMetadata = _
  private var metrics: Metrics = _

  private val offsetConfig = {
    val config = KafkaConfig.fromProps(TestUtils.createBrokerConfig(nodeId = 0, zkConnect = ""))
    OffsetConfig(maxMetadataSize = config.offsetMetadataMaxSize,
      loadBufferSize = config.offsetsLoadBufferSize,
      offsetsRetentionMs = config.offsetsRetentionMinutes * 60 * 1000L,
      offsetsRetentionCheckIntervalMs = config.offsetsRetentionCheckIntervalMs,
      offsetsTopicNumPartitions = config.offsetsTopicPartitions,
      offsetsTopicSegmentBytes = config.offsetsTopicSegmentBytes,
      offsetsTopicReplicationFactor = config.offsetsTopicReplicationFactor,
      offsetsTopicCompressionType = config.offsetsTopicCompressionType,
      offsetCommitTimeoutMs = config.offsetCommitTimeoutMs,
      offsetCommitRequiredAcks = config.offsetCommitRequiredAcks)
  }

  @org.junit.jupiter.api.AfterEach
  def tearDown(): Unit = {
    if (groupMetadataManager != null)
      groupMetadataManager.shutdown()
    if (metrics != null)
      metrics.close()
  }

  @BeforeEach
  def setUp(): Unit = {
    metrics = new Metrics()
    replicaManager = mock(classOf[ReplicaManager])
    groupMetadataManager = new GroupMetadataManager(0, MetadataVersion.latest, offsetConfig, replicaManager,
      time, metrics)
    groupMetadataManager.startup(() => numOffsetsPartitions, false)

    when(replicaManager.getMagic(any[TopicPartition]())).thenReturn(Some(RecordBatch.CURRENT_MAGIC_VALUE))

    groupMetadataManager.addOwnedPartition(groupPartitionId)

    group = new GroupMetadata(groupId, Empty, time)
    groupMetadataManager.addGroup(group)
  }

  @Test
  def testTxnOffsetAtomicityOnAppendException(): Unit = {
    val offset = 42
    val offsetAndMetadata = OffsetAndMetadata(offset, "", time.milliseconds())
    val offsets = immutable.Map(topicIdPartition -> offsetAndMetadata)

    var commitErrors: Option[immutable.Map[TopicIdPartition, Errors]] = None
    def callback(errors: immutable.Map[TopicIdPartition, Errors]): Unit = {
      commitErrors = Some(errors)
    }

    // Buggy commit uses appendRecords - mock it to throw
    when(replicaManager.appendRecords(anyLong(),
      anyShort(),
      ArgumentMatchers.eq(true),
      ArgumentMatchers.eq(AppendOrigin.COORDINATOR),
      any[Map[TopicPartition, MemoryRecords]](),
      any(),
      any[Option[ReentrantLock]](),
      any(),
      any[RequestLocal](),
      anyString(),
      any()
    )).thenThrow(new RuntimeException("Simulated log append failure"))

    assertFalse(group.hasOffsets, "Group should have no offsets before commit")

    try {
      groupMetadataManager.storeOffsets(
        group, "", offsets, callback,
        transactionalId, producerId, producerEpoch,
        RequestLocal.NoCaching
      )
    } catch {
      case e: RuntimeException =>
        if (!e.getMessage.contains("Simulated log append failure")) throw e
    }

    // KEY ASSERTION: After a failed append, the group must NOT retain pending offsets.
    if (group.hasOffsets) {
      assertTrue(group.allOffsets.isEmpty,
        "On buggy code: group.hasOffsets is true but allOffsets should be empty (pending only)")
      assertTrue(group.hasPendingOffsetCommitsFromProducer(producerId),
        "On buggy code: group should have pending txn offset commits from the failed producer")

      fail("FAIL: Atomicity violation detected (KAFKA-15784). " +
        "Group retains stale pending offsets in memory after log append exception. " +
        "prepareTxnOffsetCommit was called before appendRecords, and the failure " +
        "callback was never invoked to clean up.")
    }

    assertFalse(group.hasOffsets,
      "Group should have no offsets after failed append (in-memory state unchanged)")
  }
}
SCALAEOF
    echo "Injected regression test: $TEST_FILE"

    echo ""
    echo "Running injected test..."

    cd "$WORK_DIR"
    OUTPUT=$(./gradlew :core:test --tests "kafka.coordinator.group.TxnOffsetAtomicityTest" \
        -x spotlessCheck -x checkstyleMain -x checkstyleTest \
        --no-daemon --info 2>&1)
    TEST_EXIT=$?
    echo "$OUTPUT"

    echo ""
    if [ "$TEST_EXIT" -ne 0 ]; then
        echo "FAIL: Bug is present -- GroupMetadataManager mutates in-memory state before log append."
        echo "      When appendRecords throws, the failure callback is never invoked and"
        echo "      the group retains stale pending offsets (KAFKA-15784)."
        exit 1
    else
        echo "PASS: Bug is fixed -- in-memory state is only updated in the append callback,"
        echo "      ensuring atomicity of transactional offset commits."
        exit 0
    fi
fi
