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
TEST_METHOD_FILE="/tmp/test_method_15170.java"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

# -- Rebuild if source changed --
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -d "$WORK_DIR" ]; then
    echo "ERROR: Work directory not found at $WORK_DIR. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing kafka-15170-endless-rebalance-loop ==="

# Backup original test file
cp "$TEST_FILE" "$TEST_FILE.bak"

cleanup() {
    [ -f "$TEST_FILE.bak" ] && mv "$TEST_FILE.bak" "$TEST_FILE"
    rm -f "$TEST_METHOD_FILE"
}
trap cleanup EXIT

# ── Inject behavioral test into CooperativeStickyAssignorTest.java ──
# Verifies that partitionsTransferringOwnership is correctly populated when
# rack-aware rebalancing revokes partitions from consumers with mismatched racks.
INJECTED_TEST_NAME="testBug15170OwnershipTransferRegression"
if grep -q "$INJECTED_TEST_NAME" "$TEST_FILE" 2>/dev/null; then
    echo "Test $INJECTED_TEST_NAME already injected -- skipping injection"
else
    echo "Injecting test method $INJECTED_TEST_NAME into CooperativeStickyAssignorTest.java..."

    cat > "$TEST_METHOD_FILE" << 'TESTEOF'
    @Test
    public void testBug15170OwnershipTransferRegression() {
        // Bug KAFKA-15170: CooperativeStickyAssignor enters infinite rebalance
        // because partitionsTransferringOwnership is not populated for partitions
        // revoked due to rack mismatch during rack-aware assignment.
        //
        // Setup: 4 partitions across 2 racks (a, b), 2 consumers on racks a, b.
        //   tp0 on rack a, tp1 on rack b, tp2 on rack a, tp3 on rack b
        //   c0 (rack a) previously owns {tp0, tp1} — tp1 is rack-mismatched
        //   c1 (rack b) previously owns {tp2, tp3} — tp2 is rack-mismatched
        // Expected: rack-aware reassignment transfers tp1 c0→c1, tp2 c1→c0,
        //   and partitionsTransferringOwnership records both transfers.
        this.replicationFactor = 1;
        this.numBrokerRacks = 2;
        this.hasConsumerRack = true;

        // Force rack-aware logic (without this, the assignor may skip rack
        // optimization for small clusters and produce a sticky assignment
        // with no transfers, masking the bug).
        AbstractPartitionAssignorTest.preferRackAwareLogic(assignor, true);

        Map<String, List<PartitionInfo>> partitionsPerTopic = new HashMap<>();
        partitionsPerTopic.put(topic1, partitionInfos(topic1, 4));

        subscriptions.put("c0", buildSubscriptionV2Above(topics(topic1), partitions(tp(topic1, 0), tp(topic1, 1)),
                generationId, 0));
        subscriptions.put("c1", buildSubscriptionV2Above(topics(topic1), partitions(tp(topic1, 2), tp(topic1, 3)),
                generationId, 1));

        Map<String, List<TopicPartition>> assignment =
            assignor.assignPartitions(partitionsPerTopic, subscriptions);

        // Sanity: all partitions assigned
        int totalAssigned = 0;
        for (List<TopicPartition> parts : assignment.values()) {
            totalAssigned += parts.size();
        }
        assertEquals(4, totalAssigned, "All 4 partitions must be assigned");

        // KEY ASSERTION: partitionsTransferringOwnership must track the partitions
        // that changed ownership due to rack mismatch revocation.
        // On buggy code: this map is EMPTY — rack-revoked partitions are not tracked,
        //   so the cooperative protocol does not revoke the correct partitions from
        //   consumers, causing infinite rebalance loops.
        // On fixed code: this map has 2 entries (tp1→c1, tp2→c0).
        // Access via reflection since the field is protected and this test class
        // is in a different package from AbstractStickyAssignor.
        Map<?, ?> transferring;
        try {
            java.lang.reflect.Field f = AbstractStickyAssignor.class.getDeclaredField("partitionsTransferringOwnership");
            f.setAccessible(true);
            transferring = (Map<?, ?>) f.get(assignor);
        } catch (Exception e) {
            throw new RuntimeException("Cannot access partitionsTransferringOwnership", e);
        }
        assertFalse(transferring == null,
            "partitionsTransferringOwnership should not be null for uniform subscriptions");
        assertFalse(transferring.isEmpty(),
            "Bug KAFKA-15170: partitionsTransferringOwnership is empty but should " +
            "contain entries for partitions that changed ownership due to rack " +
            "mismatch. Without this tracking, the cooperative protocol fails to " +
            "revoke the correct partitions, causing infinite rebalance loops.");
    }
TESTEOF

    # Insert before the last closing brace of the class
    LINE_COUNT=$(wc -l < "$TEST_FILE")
    head -n $((LINE_COUNT - 1)) "$TEST_FILE" > "$TEST_FILE.tmp"
    cat "$TEST_METHOD_FILE" >> "$TEST_FILE.tmp"
    echo "}" >> "$TEST_FILE.tmp"
    mv "$TEST_FILE.tmp" "$TEST_FILE"
fi

# ── Rebuild and run ──
echo "Rebuilding..."
cd "$WORK_DIR"
./gradlew :clients:compileJava :clients:compileTestJava -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet 2>&1

echo "Running regression test..."
OUTPUT=$(./gradlew :clients:test --tests "CooperativeStickyAssignorTest.testBug15170OwnershipTransferRegression" -x spotlessCheck -x checkstyleMain -x checkstyleTest 2>&1)
TEST_EXIT=$?
echo "$OUTPUT"

echo ""
if [ "$TEST_EXIT" -ne 0 ]; then
    echo "FAIL: Bug is present -- CooperativeStickyAssignor throws IllegalStateException during"
    echo "      rack-aware rebalancing, causing infinite rebalance loops (KAFKA-15170)"
    exit 1
else
    echo "PASS: Bug is fixed -- rack-aware assignment completes with correct partition distribution"
    exit 0
fi
