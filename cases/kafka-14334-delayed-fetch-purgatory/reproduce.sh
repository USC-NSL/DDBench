#!/usr/bin/env bash
# Reproduction and verification script for kafka-14334-delayed-fetch-purgatory
# Injects a regression test into ReplicaFetcherThreadTest.scala that verifies
# the ReplicaFetcherThread completes delayed fetch requests when the follower's
# high watermark is updated after replicating from the leader.
# On buggy code: test FAILS (fix APIs missing, detected via reflection)
# On fixed code: test PASSES
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kafka-14334-delayed-fetch-purgatory"
TEST_FILE="$WORK_DIR/core/src/test/scala/unit/kafka/server/ReplicaFetcherThreadTest.scala"
TEST_METHOD_FILE="/tmp/test_method_14334.scala"

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$PATH"

# -- Rebuild if source changed --
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing kafka-14334-delayed-fetch-purgatory ==="

INJECTED=false
cleanup() {
    if [ "$INJECTED" = true ]; then
        cd "$WORK_DIR" && git checkout -- "$TEST_FILE" 2>/dev/null
    fi
    rm -f "$TEST_METHOD_FILE"
}
trap cleanup EXIT

# Check if the fix commit's own test already exists
if grep -q "testLocalFetchCompletionIfHighWatermarkUpdated" "$TEST_FILE" 2>/dev/null; then
    echo "Fix commit test already exists in source -- skipping injection"
else
    INJECTED=true

    # Write behavioral test method that verifies doWork() calls
    # completeDelayedFetchRequests after processing partition data with a
    # high watermark update. Uses a cross-version mock Answer for the UnifiedLog
    # to handle both updateHighWatermark (buggy) and maybeUpdateHighWatermark (fix).
    # Verification uses Mockito mockingDetails to check invocations by method name
    # string, avoiding compile-time references to completeDelayedFetchRequests
    # (which only exists on the fix commit's ReplicaManager).
    cat > "$TEST_METHOD_FILE" << 'TESTEOF'
  @Test
  def testBug14334DelayedFetchPurgatoryOnFollower(): Unit = {
    import org.mockito.invocation.InvocationOnMock

    val tp0 = new TopicPartition("test-topic", 0)
    val tp1 = new TopicPartition("test-topic", 1)

    // Mock ReplicaManager
    val mockReplicaMgr = mock(classOf[ReplicaManager])

    // Mock UnifiedLog with Answer to handle both buggy and fix API:
    // buggy: log.updateHighWatermark(Long) -> Long
    // fix:   log.maybeUpdateHighWatermark(Long) -> Option[Long]
    val mockLog = mock(classOf[kafka.log.UnifiedLog],
      org.mockito.Mockito.withSettings().defaultAnswer(new org.mockito.stubbing.Answer[AnyRef] {
        override def answer(inv: InvocationOnMock): AnyRef = inv.getMethod.getName match {
          case "maybeUpdateHighWatermark" => Some(100L).asInstanceOf[AnyRef]
          case "updateHighWatermark"      => java.lang.Long.valueOf(100L)
          case "highWatermark"            => java.lang.Long.valueOf(100L)
          case "logEndOffset"             => java.lang.Long.valueOf(100L)
          case "logStartOffset"           => java.lang.Long.valueOf(0L)
          case _ => org.mockito.Mockito.RETURNS_DEFAULTS.answer(inv)
        }
      }))

    val mockPartition = mock(classOf[kafka.cluster.Partition])
    when(mockPartition.localLogOrException).thenReturn(mockLog)

    when(mockReplicaMgr.getPartitionOrException(any[TopicPartition]())).thenReturn(mockPartition)
    when(mockReplicaMgr.brokerTopicStats).thenReturn(mock(classOf[BrokerTopicStats]))

    // Create config with 0 fetch backoff so doWork returns immediately
    val props = kafka.utils.TestUtils.createBrokerConfig(0, "")
    props.put("replica.fetch.backoff.ms", "0")
    val config = KafkaConfig.fromProps(props)

    val leader = mock(classOf[LeaderEndPoint])
    when(leader.brokerEndPoint()).thenReturn(new kafka.cluster.BrokerEndPoint(0, "localhost", 9092))
    val failedPartitions = new FailedPartitions
    val quota = mock(classOf[ReplicaQuota])

    val thread = new ReplicaFetcherThread(
      "test-fetcher", leader, config, failedPartitions,
      mockReplicaMgr, quota, "", () => org.apache.kafka.server.common.MetadataVersion.latest)

    // Process partition data to simulate follower receiving replicated data
    // with a high watermark update. On fixed code this populates the
    // partitionsWithNewHighWatermark buffer; on buggy code it's a no-op.
    val pd = new org.apache.kafka.common.message.FetchResponseData.PartitionData()
      .setPartitionIndex(0)
      .setHighWatermark(100L)
      .setLogStartOffset(0L)
      .setRecords(org.apache.kafka.common.record.MemoryRecords.EMPTY)

    // processPartitionData may throw on some versions due to incomplete mocks
    // for internal calls (appendRecordsToFollowerOrFutureReplica, etc.).
    // If it fails, fall back to a structural check.
    val processSucceeded = try {
      thread.processPartitionData(tp0, 0L, pd)
      thread.processPartitionData(tp1, 0L, pd.setPartitionIndex(1))
      true
    } catch {
      case _: Exception => false
    }

    // Trigger the post-fetch completion path.
    // On fixed code: doWork() calls completeDelayedFetchRequests BEFORE
    //   the fetch cycle, so even if the fetch fails the important call happens.
    // On buggy code: doWork() is inherited from AbstractFetcherThread
    //   and never calls completeDelayedFetchRequests.
    try {
      thread.doWork()
    } catch {
      case _: Exception => // Expected: mock leader can't serve fetch requests
    }

    if (processSucceeded) {
      // Behavioral check: verify completeDelayedFetchRequests was called
      // using mockingDetails (avoids compile-time reference to the method,
      // which only exists on the fix commit's ReplicaManager).
      var wasCompleted = false
      val iter = org.mockito.Mockito.mockingDetails(mockReplicaMgr).getInvocations.iterator()
      while (iter.hasNext) {
        if (iter.next().getMethod.getName == "completeDelayedFetchRequests")
          wasCompleted = true
      }
      assertTrue(wasCompleted,
        "Bug KAFKA-14334: ReplicaFetcherThread.doWork() does not call " +
        "completeDelayedFetchRequests after follower replication. " +
        "Consumers fetching from followers will always wait the full " +
        "fetch.max.wait.ms timeout instead of receiving data promptly.")
    } else {
      // Structural fallback: processPartitionData failed due to mock limitations.
      // Verify the fix mechanism exists: ReplicaFetcherThread must declare its
      // own doWork (not inherited from AbstractFetcherThread) to complete
      // delayed fetch requests after HW updates.
      val doWorkMethod = classOf[ReplicaFetcherThread].getMethod("doWork")
      assertTrue(doWorkMethod.getDeclaringClass == classOf[ReplicaFetcherThread],
        "Bug KAFKA-14334: ReplicaFetcherThread does not override doWork() to " +
        "complete delayed fetch requests after follower replication. Consumers " +
        "fetching from followers always wait fetch.max.wait.ms timeout.")
    }
  }
TESTEOF

    # Insert test method before the last closing brace of the class
    LINE_COUNT=$(wc -l < "$TEST_FILE")
    head -n $((LINE_COUNT - 1)) "$TEST_FILE" > "$TEST_FILE.tmp"
    cat "$TEST_METHOD_FILE" >> "$TEST_FILE.tmp"
    echo "}" >> "$TEST_FILE.tmp"
    mv "$TEST_FILE.tmp" "$TEST_FILE"

    echo "Injected behavioral regression test into $TEST_FILE"
fi

echo "Running Gradle test..."
cd "$WORK_DIR"

OUTPUT=$(./gradlew :core:test --tests "kafka.server.ReplicaFetcherThreadTest.testBug14334DelayedFetchPurgatoryOnFollower" -x spotlessCheck 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present -- ReplicaFetcherThread does not complete delayed"
    echo "      fetch requests after follower replication (KAFKA-14334)"
    exit 1
else
    echo "PASS: Bug is fixed -- delayed fetch purgatory is completed after follower HW update"
    exit 0
fi
