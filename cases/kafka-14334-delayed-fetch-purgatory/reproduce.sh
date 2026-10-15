#!/usr/bin/env bash
# Reproduction and verification script for kafka-14334-delayed-fetch-purgatory
# Starts two brokers in-process with fetch from follower enabled and a topic that
# broker 0 leads and broker 1 follows. A consumer fetch (minBytes=1, maxWait=30 s)
# is sent to the follower before anything is produced; then a record is produced
# to the leader (acks=all). The follower must answer the waiting fetch with that
# record within 10 s of the acknowledgement, not when the fetch's maxWait expires.
# Done twice (1.5 s and 15 s between the fetch and the produce).
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

# ── JUnit XML verdict ──
# Decided from the JUnit XML report for the exact oracle test case. Never from
# console text. A failure whose exception type is the oracle's setup exception
# means the oracle could not establish its preconditions (inconclusive).
SETUP_EXCEPTION=kafka.server.DDBenchOracleSetupException
junit_result() {  # <xml-file> <test-method> -> pass | fail | setup | skip | norun
    [ -f "$1" ] || { echo norun; return; }
    awk -v m="$2" -v setup="type=\"$SETUP_EXCEPTION\"" '
        function check(line) {
            if (line ~ /<(failure|error)[ >\/]/) { bad = 1; if (index(line, setup)) su = 1 }
            if (line ~ /<skipped/) skip = 1
        }
        /<testcase[ >]/ {
            inc = ($0 ~ ("name=\"" m "([({[][^\"]*)?\""))
            if (inc) { found = 1; check($0)
                if ($0 ~ /\/>[[:space:]]*$/ || $0 ~ /<\/testcase>/) inc = 0 }
            next }
        inc { check($0) }
        inc && /<\/testcase>/ { inc = 0 }
        END {
            if (!found) print "norun"
            else if (su) print "setup"
            else if (bad) print "fail"
            else if (skip) print "skip"
            else print "pass"
        }
    ' "$1"
}

ORACLE_CLASS=kafka.server.DDBenchOracleFetchFromFollowerTest
ORACLE_METHOD=testDDBenchOracleFollowerAnswersWaitingFetchOnReplication
ORACLE_FILE=DDBenchOracleFetchFromFollowerTest.scala
INIT_SCRIPT=ddbench-oracle.init.gradle
LOG4J_CONFIG=log4j.properties
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
[ -f "$WORK_DIR/core/src/main/scala/kafka/server/KafkaServer.scala" ] || error "kafka core sources not found in $WORK_DIR (run setup first)"
for f in "$ORACLE_FILE" "$INIT_SCRIPT" "$LOG4J_CONFIG"; do
    [ -f "$CASE_DIR/inject_test/$f" ] || error "oracle harness file inject_test/$f is missing"
done

echo "=== Reproducing kafka-14334-delayed-fetch-purgatory ==="

# The oracle test is compiled from $RUN_DIR (outside the worktree) in its own
# source set of :core; nothing in the worktree can stand in for it.
mkdir -p "$RUN_DIR/oracle-src/kafka/server" "$RUN_DIR/oracle-resources"
cp "$CASE_DIR/inject_test/$ORACLE_FILE" "$RUN_DIR/oracle-src/kafka/server/$ORACLE_FILE"
cp "$CASE_DIR/inject_test/$LOG4J_CONFIG" "$RUN_DIR/oracle-resources/$LOG4J_CONFIG"
cp "$CASE_DIR/inject_test/$INIT_SCRIPT" "$RUN_DIR/$INIT_SCRIPT"
remove_oracle_outputs

cd "$WORK_DIR"
echo "Running $ORACLE_CLASS.$ORACLE_METHOD ..."
DDBENCH_ORACLE_SRC="$RUN_DIR/oracle-src" DDBENCH_ORACLE_RESOURCES="$RUN_DIR/oracle-resources" \
    ./gradlew --init-script "$RUN_DIR/$INIT_SCRIPT" :core:ddbenchOracleTest --no-daemon > "$LOG" 2>&1
GRADLE_RC=$?
grep -E "DDBench oracle:|DDBenchOracle.*(PASSED|FAILED|SKIPPED)|^FAILURE|What went wrong|error:|Compilation failed" "$LOG" | head -40
echo "(gradle exited $GRADLE_RC)"

if [ -f "$REPORT" ]; then   # the assertion or setup message, for humans
    grep -oE '<(failure|error) message="[^"]*"' "$REPORT" | sed -e 's/^<[a-z]* message="/  /' -e 's/"$//' \
        -e 's/&quot;/"/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e "s/&apos;/'/g" -e 's/&amp;/\&/g' | head -5
fi

case "$(junit_result "$REPORT" "$ORACLE_METHOD")" in
    pass)
        pass "Bug is fixed — the follower answers a consumer fetch waiting for data promptly (with the record) once the record is replicated to it" ;;
    fail)
        fail "Bug is present — a consumer fetch waiting on the follower is not answered promptly with the replicated record (see the message above)" ;;
    setup)
        tail -40 "$LOG"
        error "the oracle could not establish its preconditions (cluster, topic, replication or a responsive leader; see the message above)" ;;
    skip)
        fail "the oracle test was skipped" ;;
    *)
        tail -40 "$LOG"
        if grep -qE "COMPILATION ERROR|Compilation failure|compilation failed|Compilation failed|error: |cannot find symbol" "$LOG"; then
            fail "the oracle test did not run: the worktree or the injected oracle test does not compile"
        fi
        error "the oracle test did not run and no compilation error was found (see output above)" ;;
esac
