#!/usr/bin/env bash
# Reproduction and verification script for <case-name>
# Injects the Go regression test from the case's inject_test.go into GO_PACKAGE_DIR
# and runs it TEST_ITERATIONS times; any failing run means the bug is present.
# TODO: one line on what the test checks, in observable terms.
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
# go_oracle <TestName> <package> [go test flags...]: run exactly one test from
# the current directory. Sets GO_RESULT (pass|fail|skip|norun) and GO_LOG.
go_oracle() {
    local name="$1" pkg="$2"; shift 2
    GO_LOG="$RUN_DIR/go-test-$name-$RANDOM.json"
    go test -json -count=1 -run "^${name}\$" "$@" "$pkg" > "$GO_LOG" 2>&1
    go_test_transcript "$GO_LOG" | tail -n 40
    GO_RESULT=$(go_test_result "$GO_LOG" "$name")
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
TOTAL=TEST_ITERATIONS

cleanup() { rm -f "$ORACLE_FILE"; rm -rf "$RUN_DIR"; }
trap cleanup EXIT

rebuild_worktree
[ -d "$MODULE_DIR/GO_PACKAGE_DIR" ] || error "package GO_PACKAGE_DIR not found in $MODULE_DIR (run setup first)"
cd "$MODULE_DIR" || error "module directory $MODULE_DIR not found (run setup first)"

echo "=== Reproducing <case-name> ==="

# The oracle test is always injected fresh, under a ddbench-only name and file.
# It is read from the case directory (/bench) at run time; builds never copy it
# into the worktree.
[ -f "$CASE_DIR/inject_test.go" ] || error "oracle test $CASE_DIR/inject_test.go missing"
cp "$CASE_DIR/inject_test.go" "$ORACLE_FILE" || error "could not inject the oracle test"

for i in $(seq 1 "$TOTAL"); do
    echo "=== Run $i/$TOTAL ==="
    go_oracle "$ORACLE" "$PKG" -timeout 90s
    case "$GO_RESULT" in
        pass) echo "Run $i: passed" ;;
        fail) fail "Bug is present — FAIL_DESCRIPTION (run $i/$TOTAL)" ;;
        skip) fail "the oracle test was skipped" ;;
        *)    go_norun_verdict "$GO_LOG" ;;
    esac
done
pass "Bug is fixed — PASS_DESCRIPTION (all $TOTAL runs passed)"
