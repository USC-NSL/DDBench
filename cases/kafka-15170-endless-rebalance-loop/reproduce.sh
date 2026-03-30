#!/usr/bin/env bash
# Reproduction and verification script for kafka-15170-endless-rebalance-loop
# Injects regression test into CooperativeStickyAssignorTest.java and adds
# a partitionsTransferringOwnership() accessor to AbstractStickyAssignor.
# On buggy code: test FAILS (partitionsTransferringOwnership is empty → infinite rebalance)
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
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kafka-15170-endless-rebalance-loop"

TEST_FILE="$WORK_DIR/clients/src/test/java/org/apache/kafka/clients/consumer/CooperativeStickyAssignorTest.java"
ASSIGNOR_FILE="$WORK_DIR/clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractStickyAssignor.java"
TEST_METHOD_FILE="/tmp/test_method_15170.java"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing kafka-15170-endless-rebalance-loop ==="

# Backup original files
cp "$TEST_FILE" "$TEST_FILE.bak"
cp "$ASSIGNOR_FILE" "$ASSIGNOR_FILE.bak"

cleanup() {
    [ -f "$TEST_FILE.bak" ] && mv "$TEST_FILE.bak" "$TEST_FILE"
    [ -f "$ASSIGNOR_FILE.bak" ] && mv "$ASSIGNOR_FILE.bak" "$ASSIGNOR_FILE"
    rm -f "$TEST_METHOD_FILE"
}
trap cleanup EXIT

# ── Step 1: Add partitionsTransferringOwnership() accessor to AbstractStickyAssignor ──
if ! grep -q "public Map<TopicPartition, String> partitionsTransferringOwnership()" "$ASSIGNOR_FILE" 2>/dev/null; then
    echo "Adding partitionsTransferringOwnership() accessor to AbstractStickyAssignor..."
    # Insert accessor after the field declaration using sed
    sed -i '/protected Map<TopicPartition, String> partitionsTransferringOwnership = new HashMap<>();/a\
\    public Map<TopicPartition, String> partitionsTransferringOwnership() {\
        return partitionsTransferringOwnership;\
    }' "$ASSIGNOR_FILE"
fi

# ── Step 2: Inject test method into CooperativeStickyAssignorTest.java ──
# Use a unique test name to avoid conflict with the fix commit's own test
INJECTED_TEST_NAME="testBug15170OwnershipTransferRegression"
if grep -q "$INJECTED_TEST_NAME" "$TEST_FILE" 2>/dev/null; then
    echo "Test $INJECTED_TEST_NAME already injected -- skipping injection"
else
    echo "Injecting test method $INJECTED_TEST_NAME into CooperativeStickyAssignorTest.java..."

    # Write test method to temp file
    cat > "$TEST_METHOD_FILE" << 'TESTEOF'
    @Test
    public void testBug15170OwnershipTransferRegression() {
        this.replicationFactor = 1;
        this.numBrokerRacks = 2;
        this.hasConsumerRack = true;
        Map<String, List<PartitionInfo>> partitionsPerTopic = new HashMap<>();
        partitionsPerTopic.put(topic1, partitionInfos(topic1, 4));

        subscriptions.put("c0", buildSubscriptionV2Above(topics(topic1), partitions(tp(topic1, 0), tp(topic1, 1)),
                generationId, 0));
        subscriptions.put("c1", buildSubscriptionV2Above(topics(topic1), partitions(tp(topic1, 2), tp(topic1, 3)),
                generationId, 1));

        assignor.assignPartitions(partitionsPerTopic, subscriptions);
        assertEquals(2, assignor.partitionsTransferringOwnership().size());
    }
TESTEOF

# Insert before the last closing brace of the class
# Use tac + sed to find the LAST } (which is the class closing brace)
LINE_COUNT=$(wc -l < "$TEST_FILE")
head -n $((LINE_COUNT - 1)) "$TEST_FILE" > "$TEST_FILE.tmp"
cat "$TEST_METHOD_FILE" >> "$TEST_FILE.tmp"
echo "}" >> "$TEST_FILE.tmp"
mv "$TEST_FILE.tmp" "$TEST_FILE"
fi

# ── Step 3: Rebuild and run ──
echo "Rebuilding..."
cd "$WORK_DIR"
./gradlew :clients:compileJava :clients:compileTestJava -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet 2>&1

echo "Running regression test..."
OUTPUT=$(./gradlew :clients:test --tests "CooperativeStickyAssignorTest.testBug15170OwnershipTransferRegression" -x spotlessCheck -x checkstyleMain -x checkstyleTest 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present -- CooperativeStickyAssignor fails to correctly populate partitionsTransferringOwnership during rack-aware rebalancing, causing infinite rebalance loops"
    exit 1
else
    echo "PASS: Bug is fixed -- partitionsTransferringOwnership is correctly populated"
    exit 0
fi
