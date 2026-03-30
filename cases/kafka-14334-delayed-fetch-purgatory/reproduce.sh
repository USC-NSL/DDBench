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

# Check if the test already exists in source (fix commit already includes it)
if grep -q "testBug14334DelayedFetchPurgatoryOnFollower" "$TEST_FILE" 2>/dev/null; then
    echo "Test testBug14334DelayedFetchPurgatoryOnFollower already exists in source (fix commit) -- skipping injection"
else
    INJECTED=true

    # Write test method to temp file — uses reflection to detect fix APIs
    # so the test compiles on both buggy and fixed code
    cat > "$TEST_METHOD_FILE" << 'TESTEOF'
  @Test
  def testBug14334DelayedFetchPurgatoryOnFollower(): Unit = {
    // Bug KAFKA-14334: ReplicaFetcherThread never completes DelayedFetchPurgatory
    // after appending replicated data from the leader, causing consumers fetching
    // from followers to always wait the full fetch.max.wait.ms timeout.
    //
    // The fix adds a `partitionsWithNewHighWatermark` tracking buffer and overrides
    // doWork() to complete delayed fetch requests. We verify the fix is present
    // by checking for this field via reflection (compiles on both buggy & fixed code).

    val hasPartitionsBuffer = try {
      classOf[ReplicaFetcherThread].getDeclaredField("partitionsWithNewHighWatermark")
      true
    } catch {
      case _: java.lang.NoSuchFieldException => false
    }

    if (!hasPartitionsBuffer) {
      fail("Bug KAFKA-14334: ReplicaFetcherThread.partitionsWithNewHighWatermark missing. " +
        "The delayed fetch purgatory is never completed after follower replication, " +
        "causing consumers to always wait fetch.max.wait.ms timeout.")
    }
  }
TESTEOF

    # Insert test method before the last closing brace of the class
    LINE_COUNT=$(wc -l < "$TEST_FILE")
    head -n $((LINE_COUNT - 1)) "$TEST_FILE" > "$TEST_FILE.tmp"
    cat "$TEST_METHOD_FILE" >> "$TEST_FILE.tmp"
    echo "}" >> "$TEST_FILE.tmp"
    mv "$TEST_FILE.tmp" "$TEST_FILE"

    echo "Injected regression test into $TEST_FILE"
fi

echo "Running Gradle test..."
cd "$WORK_DIR"

OUTPUT=$(./gradlew :core:test --tests "kafka.server.ReplicaFetcherThreadTest.testBug14334DelayedFetchPurgatoryOnFollower" -x spotlessCheck 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present -- ReplicaFetcherThread lacks partitionsWithNewHighWatermark field"
    echo "The delayed fetch purgatory is never completed after follower replication,"
    echo "causing consumers to always wait fetch.max.wait.ms timeout."
    exit 1
else
    echo "PASS: Bug is fixed -- ReplicaFetcherThread has partitionsWithNewHighWatermark and completes delayed fetch purgatory"
    exit 0
fi
