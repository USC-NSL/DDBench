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

TEST_FILE="$WORK_DIR/core/src/test/scala/unit/kafka/coordinator/group/TxnOffsetAtomicityTest.scala"

# Always remove stale injected test
rm -f "$TEST_FILE"

INJECTED=true
cleanup() {
    [ "$INJECTED" = true ] && rm -f "$TEST_FILE"
}
trap cleanup EXIT

# Inject a behavioral test that detects the atomicity violation.
# Uses reflection to call storeOffsets so it compiles on both
# the buggy API (transactionalId param) and the fix API (verificationGuard param).
# Also uses a custom Mockito Answer to intercept any append* method call,
# handling both appendRecords (buggy) and appendForGroup (fix).
cat > "$TEST_FILE" << 'SCALAEOF'
package kafka.coordinator.group

import java.util.concurrent.locks.ReentrantLock
import kafka.common.OffsetAndMetadata
import kafka.server.{KafkaConfig, ReplicaManager, RequestLocal}
import kafka.utils.TestUtils
import org.apache.kafka.common.{TopicIdPartition, TopicPartition, Uuid}
import org.apache.kafka.common.metrics.Metrics
import org.apache.kafka.common.record.RecordBatch
import org.apache.kafka.common.protocol.Errors
import org.apache.kafka.server.common.MetadataVersion
import org.apache.kafka.server.util.MockTime
import org.junit.jupiter.api.Assertions._
import org.junit.jupiter.api.{AfterEach, BeforeEach, Test}
import org.mockito.ArgumentMatchers._
import org.mockito.Mockito._
import org.mockito.invocation.InvocationOnMock
import org.mockito.stubbing.Answer

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

  @AfterEach
  def tearDown(): Unit = {
    if (groupMetadataManager != null)
      groupMetadataManager.shutdown()
    if (metrics != null)
      metrics.close()
  }

  @BeforeEach
  def setUp(): Unit = {
    metrics = new Metrics()
    // Use a custom default answer that throws on any append* method,
    // handling both appendRecords (buggy API) and appendForGroup (fix API)
    replicaManager = mock(classOf[ReplicaManager], withSettings().defaultAnswer(new Answer[AnyRef] {
      override def answer(invocation: InvocationOnMock): AnyRef = {
        if (invocation.getMethod.getName.startsWith("append"))
          throw new RuntimeException("Simulated log append failure")
        org.mockito.Mockito.RETURNS_DEFAULTS.answer(invocation)
      }
    }))
    when(replicaManager.getMagic(any[TopicPartition]())).thenReturn(Some(RecordBatch.CURRENT_MAGIC_VALUE))

    groupMetadataManager = new GroupMetadataManager(0, MetadataVersion.latest, offsetConfig, replicaManager,
      time, metrics)
    groupMetadataManager.startup(() => numOffsetsPartitions, false)
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

    assertFalse(group.hasOffsets, "Group should have no offsets before commit")

    // Call storeOffsets via reflection to handle both buggy and fix API signatures.
    // Buggy API: storeOffsets(group, consumerId, offsets, callback, txnId, prodId, prodEpoch, requestLocal)
    // Fix API may add/change parameters (e.g., verificationGuard instead of txnId).
    val storeMethod = groupMetadataManager.getClass.getMethods
      .filter(_.getName == "storeOffsets")
      .filter(_.getParameterCount >= 7)
      .sortBy(-_.getParameterCount)
      .head

    val paramTypes = storeMethod.getParameterTypes
    val args = new Array[AnyRef](paramTypes.length)
    // First 4 args are always: group, consumerId, offsets, callback
    args(0) = group
    args(1) = ""
    args(2) = offsets
    args(3) = callback.asInstanceOf[AnyRef]
    // Remaining args: fill based on type
    for (i <- 4 until paramTypes.length) {
      val pt = paramTypes(i)
      args(i) = {
        if (pt == classOf[String]) transactionalId
        else if (pt == java.lang.Long.TYPE || pt == classOf[java.lang.Long]) java.lang.Long.valueOf(producerId)
        else if (pt == java.lang.Short.TYPE || pt == classOf[java.lang.Short]) java.lang.Short.valueOf(producerEpoch)
        else if (pt.getSimpleName.contains("RequestLocal")) RequestLocal.NoCaching
        else if (pt.getSimpleName.contains("Optional")) java.util.Optional.empty()
        else null
      }
    }

    try {
      storeMethod.invoke(groupMetadataManager, args: _*)
    } catch {
      case e: java.lang.reflect.InvocationTargetException =>
        val cause = e.getCause
        if (cause == null || !cause.getMessage.contains("Simulated log append failure")) throw e
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
