#!/usr/bin/env bash
# Reproduction and verification script for kafka-15784-txn-offset-atomicity
# Runs a single-broker group coordinator on a real __consumer_offsets log with
# transaction verification enabled. A transactional producer commits offsets for
# its group while the group is deleted, or while the coordinator unloads and
# reloads the offsets partition; then the transaction completes. The offset the
# live coordinator serves must equal the offset a coordinator serves after
# reloading the log, and an acknowledged, committed offset must be served.
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
# Decided from the JUnit XML report for the exact oracle test cases: each must
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

ORACLE_CLASS=kafka.coordinator.group.DDBenchOracleTxnOffsetCommitTest
ORACLE_FILE=DDBenchOracleTxnOffsetCommitTest.scala
INIT_SCRIPT=ddbench-oracle.init.gradle
# Baseline (no concurrent event), then the two concurrent events.
ORACLE_METHODS="testDDBenchOracleTxnOffsetCommitBaseline testDDBenchOracleGroupDeletedDuringTxnOffsetCommit testDDBenchOracleCoordinatorReloadDuringTxnOffsetCommit"
REPORT="$WORK_DIR/core/build/test-results/ddbenchOracleTest/TEST-$ORACLE_CLASS.xml"
LOG="$RUN_DIR/gradle-test.log"

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$PATH"

# Everything compiled or reported for the oracle source set (core/build/*/ddbenchOracle*).
remove_oracle_outputs() {
    [ -d "$WORK_DIR/core/build" ] || return 0
    find "$WORK_DIR/core/build" -maxdepth 5 -iname '*ddbenchoracle*' -prune -exec rm -rf {} + 2>/dev/null
    return 0
}
cleanup() {
    remove_oracle_outputs
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

rebuild_worktree
[ -d "$WORK_DIR/core/src/main/scala/kafka/coordinator/group" ] || error "kafka core sources not found in $WORK_DIR (run setup first)"
for f in "$ORACLE_FILE" "$INIT_SCRIPT"; do
    [ -f "$CASE_DIR/inject_test/$f" ] || error "oracle harness file inject_test/$f is missing"
done

echo "=== Reproducing kafka-15784-txn-offset-atomicity ==="

# The oracle test is compiled from $RUN_DIR (outside the worktree) in its own
# source set of :core; nothing in the worktree can stand in for it.
mkdir -p "$RUN_DIR/oracle-src/kafka/coordinator/group"
cp "$CASE_DIR/inject_test/$ORACLE_FILE" "$RUN_DIR/oracle-src/kafka/coordinator/group/$ORACLE_FILE"
cp "$CASE_DIR/inject_test/$INIT_SCRIPT" "$RUN_DIR/$INIT_SCRIPT"
remove_oracle_outputs

cd "$WORK_DIR"
echo "Running $ORACLE_CLASS ..."
DDBENCH_ORACLE_SRC="$RUN_DIR/oracle-src" ./gradlew --init-script "$RUN_DIR/$INIT_SCRIPT" \
    :core:ddbenchOracleTest --no-daemon > "$LOG" 2>&1
GRADLE_RC=$?
grep -E "DDBench oracle:|DDBenchOracle.*(PASSED|FAILED|SKIPPED)|AssertionFailedError|^FAILURE|What went wrong|error:|Compilation failed" "$LOG" | head -60
echo "(gradle exited $GRADLE_RC)"

if [ -f "$REPORT" ]; then   # assertion messages, for humans
    grep -oE '<(failure|error) message="[^"]*"' "$REPORT" | sed -e 's/^<[a-z]* message="/  /' -e 's/"$//' \
        -e 's/&quot;/"/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e "s/&apos;/'/g" -e 's/&amp;/\&/g' | head -10
fi
failed=""; skipped=""; norun=""
for m in $ORACLE_METHODS; do
    r=$(junit_result "$REPORT" "$m")
    echo "  $m: $r"
    case "$r" in
        pass) ;;
        fail) failed="$failed $m" ;;
        skip) skipped="$skipped $m" ;;
        *)    norun="$norun $m" ;;
    esac
done

if [ -n "$failed" ]; then
    fail "Bug is present — the coordinator's served offsets disagree with the offsets log, or an acknowledged transactional offset commit is not served (failed:$failed)"
fi
if [ -n "$skipped" ]; then
    fail "an oracle test was skipped:$skipped"
fi
if [ -n "$norun" ]; then
    tail -40 "$LOG"
    if grep -qE "COMPILATION ERROR|Compilation failure|compilation failed|Compilation failed|error: |cannot find symbol" "$LOG"; then
        fail "the oracle test did not run: the worktree or the injected oracle test does not compile"
    fi
    error "the oracle test did not run and no compilation error was found (see output above)"
fi
pass "Bug is fixed — transactional offset commits racing with group deletion or a coordinator reload leave the served offsets equal to the offsets log"
