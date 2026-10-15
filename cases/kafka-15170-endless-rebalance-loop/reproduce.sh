#!/usr/bin/env bash
# Reproduction and verification script for kafka-15170-endless-rebalance-loop
# Injects a test method into CooperativeStickyAssignorTest (clients): in a
# rack-aware cooperative rebalance where each consumer owns a partition on the
# other consumer's rack, no partition may be handed to a new consumer in the
# same rebalance that takes it from its current owner (cooperative protocol).
#
# Exit codes: 0 = PASS (bug fixed), 1 = FAIL (bug present, or the worktree does
# not build / the code under test does not start), 2 = ERROR (oracle or
# infrastructure problem; the verdict is inconclusive).
# ── Runs only inside the bench.sh reproduce container (BENCH_WORKDIR is set) ──
if [ -z "${BENCH_WORKDIR:-}" ]; then
    CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    [ -f "$REPO_ROOT/bench.sh" ] && exec bash "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
    echo "ERROR: run this oracle with ./bench.sh reproduce $CASE_NAME" >&2
    exit 2
fi
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$BENCH_WORKDIR"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ddbench.XXXXXX")"   # scratch space outside the worktree

pass()  { echo ""; echo "PASS: $*"; exit 0; }
fail()  { echo ""; echo "FAIL: $*"; exit 1; }
error() { echo ""; echo "ERROR: $*"; exit 2; }

# REBUILD.sh is the worktree's designated build entry point.
rebuild_worktree() {
    [ -f "$WORK_DIR/REBUILD.sh" ] || error "REBUILD.sh not found in $WORK_DIR (run setup first)"
    bash "$WORK_DIR/REBUILD.sh" || fail "the worktree does not build (REBUILD.sh exited non-zero)"
}

# ── JUnit XML verdicts ──
# Decided from the JUnit XML report for the exact oracle test case: it must
# exist and contain no <failure>, <error> or <skipped>. Never from console text.
junit_result() {  # <xml-file> <test-method> -> pass | fail | skip | norun
    [ -f "$1" ] || { echo norun; return; }
    awk -v m="$2" '
        /<testcase[ >]/ {
            inc = ($0 ~ ("name=\"" m "([({[][^\"]*)?\""))
            if (inc) { found = 1
                if ($0 ~ /<(failure|error)[ >\/]/) bad = 1
                if ($0 ~ /<skipped/) skip = 1
                if ($0 ~ /\/>[[:space:]]*$/ || $0 ~ /<\/testcase>/) inc = 0 }
            next }
        inc && /<(failure|error)[ >\/]/ { bad = 1 }
        inc && /<skipped/ { skip = 1 }
        inc && /<\/testcase>/ { inc = 0 }
        END { if (!found) print "norun"; else if (bad) print "fail"; else if (skip) print "skip"; else print "pass" }
    ' "$1"
}
# Exit with the verdict for the oracle test case.
junit_verdict() {  # <xml> <method> <console-log> <pass-message> <fail-message>
    case "$(junit_result "$1" "$2")" in
        pass) pass "$4" ;;
        fail) fail "$5" ;;
        skip) fail "the oracle test was skipped" ;;
        *)
            if grep -qE "COMPILATION ERROR|Compilation failure|compilation failed|Compilation failed|error: |cannot find symbol" "$3"; then
                fail "the oracle test did not run: the worktree or the injected oracle test does not compile"
            fi
            error "the oracle test did not run and no compilation error was found (see output above)" ;;
    esac
}

TEST_FILE="$WORK_DIR/clients/src/test/java/org/apache/kafka/clients/consumer/CooperativeStickyAssignorTest.java"
TEST_METHOD=testDDBenchOracleRackAwareOwnershipTransfer
REPORT="$WORK_DIR/clients/build/test-results/test/TEST-org.apache.kafka.clients.consumer.CooperativeStickyAssignorTest.xml"
LOG="$RUN_DIR/gradle-test.log"

export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}
export PATH="$JAVA_HOME/bin:$PATH"

rebuild_worktree
[ -f "$TEST_FILE" ] || error "CooperativeStickyAssignorTest.java not found in $WORK_DIR (run setup first)"

echo "=== Reproducing kafka-15170-endless-rebalance-loop ==="

# Always inject, under a ddbench-only method name; the worktree's version of
# the test file is restored afterwards.
cp "$TEST_FILE" "$RUN_DIR/CooperativeStickyAssignorTest.java.saved"
cleanup() {
    cp "$RUN_DIR/CooperativeStickyAssignorTest.java.saved" "$TEST_FILE"
    # Reports and classes compiled from the injected test must not outlive the run.
    rm -f "$REPORT"; rm -rf "$WORK_DIR/clients/build/reports/tests"
    rm -f "$WORK_DIR"/clients/build/classes/java/test/org/apache/kafka/clients/consumer/CooperativeStickyAssignorTest*.class
}
trap cleanup EXIT

cat > "$RUN_DIR/method.java" << 'TESTEOF'
    @Test
    public void testDDBenchOracleRackAwareOwnershipTransfer() {
        // 4 partitions on 2 racks; c0 (rack 0) owns {tp0, tp1} and c1 (rack 1)
        // owns {tp2, tp3}, so tp1 and tp2 sit on the other consumer's rack.
        this.replicationFactor = 1;
        this.numBrokerRacks = 2;
        this.hasConsumerRack = true;
        AbstractPartitionAssignorTest.preferRackAwareLogic(assignor, true);

        Map<String, List<PartitionInfo>> partitionsPerTopic = new HashMap<>();
        partitionsPerTopic.put(topic1, partitionInfos(topic1, 4));
        Map<String, List<TopicPartition>> owned = new HashMap<>();
        owned.put("c0", partitions(tp(topic1, 0), tp(topic1, 1)));
        owned.put("c1", partitions(tp(topic1, 2), tp(topic1, 3)));
        subscriptions.put("c0", buildSubscriptionV2Above(topics(topic1), owned.get("c0"), generationId, 0));
        subscriptions.put("c1", buildSubscriptionV2Above(topics(topic1), owned.get("c1"), generationId, 1));

        Map<String, List<TopicPartition>> assignment =
            assignor.assignPartitions(partitionsPerTopic, subscriptions);

        // Cooperative rebalancing: a partition may only move to a new consumer
        // after its current owner has revoked it, i.e. never in the same
        // rebalance in which it is taken away. (Partitions being moved are left
        // unassigned in this round and assigned in a follow-up rebalance.)
        Set<TopicPartition> seen = new HashSet<>();
        for (Map.Entry<String, List<TopicPartition>> e : assignment.entrySet()) {
            for (TopicPartition p : e.getValue()) {
                assertTrue(seen.add(p), p + " assigned to more than one consumer: " + assignment);
                for (Map.Entry<String, List<TopicPartition>> o : owned.entrySet()) {
                    assertFalse(!o.getKey().equals(e.getKey()) && o.getValue().contains(p),
                        p + " was assigned to " + e.getKey() + " while still owned by " + o.getKey()
                            + " (cooperative protocol violated): " + assignment);
                }
            }
        }
    }
TESTEOF
LINE_COUNT=$(wc -l < "$TEST_FILE")
{ head -n $((LINE_COUNT - 1)) "$TEST_FILE"; cat "$RUN_DIR/method.java"; echo "}"; } > "$RUN_DIR/injected.java"
cp "$RUN_DIR/injected.java" "$TEST_FILE"

cd "$WORK_DIR"
rm -f "$REPORT"
echo "Running $TEST_METHOD ..."
./gradlew :clients:test --tests "CooperativeStickyAssignorTest.$TEST_METHOD" \
    -x spotlessCheck -x checkstyleMain -x checkstyleTest > "$LOG" 2>&1
tail -40 "$LOG"
junit_verdict "$REPORT" "$TEST_METHOD" "$LOG" \
    "Bug is fixed — rack-aware cooperative assignment completes with a valid assignment" \
    "Bug is present — rack-aware cooperative rebalancing fails to account for partitions changing owner"
