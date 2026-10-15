#!/usr/bin/env bash
# Reproduction and verification script for <case-name>
# Injects the Go test from the case's inject_test.go and runs it with the race
# detector RACE_ITERATIONS times; a data race in any run means the bug is present.
# TODO: one line on what the test exercises, in observable terms.
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

# ── Go test verdicts ──
# Decided from `go test -json` events for the exact oracle test, never from free
# text (code under test can print anything). A test that did not run is no pass.
go_test_result() {  # <json-log> <TestName> -> pass | fail | skip | norun
    local pre='^\{("Time":"[^"]*",)?"Action":"' post="\",\"Package\":\"[^\"]*\",\"Test\":\"$2\"[,}]"
    if   grep -qE "${pre}fail${post}" "$1"; then echo fail
    elif grep -qE "${pre}pass${post}" "$1"; then echo pass
    elif grep -qE "${pre}skip${post}" "$1"; then echo skip
    else echo norun; fi
}
go_test_transcript() {  # human-readable form of a -json log
    sed -n -e '/^{/!p' -e 's/^{.*"Action":"output".*"Output":"\(.*\)"}$/\1/p' "$1" \
        | sed -e 's/\\n$//' -e 's/\\t/	/g' -e 's/\\"/"/g' -e 's/\\u003c/</g' \
              -e 's/\\u003e/>/g' -e 's/\\u0026/\&/g' -e 's/\\\\/\\/g'
}
# Verdict when the oracle test produced no result.
go_norun_verdict() {  # <json-log>
    if grep -qE 'dial tcp|i/o timeout|TLS handshake timeout|no such host|connection reset by peer' "$1" \
       && ! grep -qE '\.go:[0-9]+:[0-9]+: ' "$1"; then
        error "the oracle test did not run: Go module download failed (network)"
    fi
    fail "the oracle test did not run (the package or the injected oracle test does not compile)"
}

MODULE_DIR="$WORK_DIR/GO_MODULE_ROOT"        # directory that holds go.mod ("." for the worktree root)
PKG="./GO_PACKAGE_DIR"                       # package under test, relative to MODULE_DIR
ORACLE=ORACLE_TEST_NAME                      # the test in inject_test.go; must start with TestDDBenchOracle
ORACLE_FILE="$MODULE_DIR/GO_PACKAGE_DIR/zz_ddbench_oracle_test.go"
TOTAL=RACE_ITERATIONS

cleanup() { rm -f "$ORACLE_FILE"; rm -rf "$RUN_DIR"; }
trap cleanup EXIT

rebuild_worktree
[ -d "$MODULE_DIR/GO_PACKAGE_DIR" ] || error "package GO_PACKAGE_DIR not found in $MODULE_DIR (run setup first)"
cd "$MODULE_DIR" || error "module directory $MODULE_DIR not found (run setup first)"

echo "=== Reproducing <case-name> ==="

# The oracle test is always injected fresh, under a ddbench-only name and file.
[ -f "$CASE_DIR/inject_test.go" ] || error "oracle test $CASE_DIR/inject_test.go missing"
cp "$CASE_DIR/inject_test.go" "$ORACLE_FILE" || error "could not inject the oracle test"

echo "Running $ORACLE with the race detector ($TOTAL runs) ..."
for i in $(seq 1 "$TOTAL"); do
    echo "=== Run $i/$TOTAL (-race) ==="
    GO_LOG="$RUN_DIR/race-$i.json"
    rc=0
    timeout 150 go test -json -race -count=1 -run "^${ORACLE}\$" -timeout 120s "$PKG" > "$GO_LOG" 2>&1 || rc=$?
    # The race detector's report is the bug signal. Printing it can only turn a
    # run into FAIL; a PASS still needs the oracle test's own "pass" event below.
    if grep -qE 'WARNING: DATA RACE|race detected during execution of test' "$GO_LOG"; then
        go_test_transcript "$GO_LOG" | grep -A 20 'DATA RACE' | head -30
        fail "Bug is present — data race detected in run $i/$TOTAL"
    fi
    [ "$rc" -eq 124 ] && fail "the oracle test did not finish within 150s in run $i/$TOTAL"
    GO_RESULT=$(go_test_result "$GO_LOG" "$ORACLE")
    case "$GO_RESULT" in
        pass) echo "Run $i: test passed, no race detected" ;;
        fail) go_test_transcript "$GO_LOG" | tail -30; fail "the oracle test failed in run $i/$TOTAL" ;;
        skip) fail "the oracle test was skipped" ;;
        *)    go_test_transcript "$GO_LOG" | tail -30; go_norun_verdict "$GO_LOG" ;;
    esac
done
pass "Bug is fixed — all $TOTAL race-detector runs passed without a data race"
