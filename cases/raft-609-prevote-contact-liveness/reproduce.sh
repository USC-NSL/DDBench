#!/usr/bin/env bash
# Reproduction and verification script for raft-609-prevote-contact-liveness
# Injects an integration test (TCP transport, INTEG_TESTS=1) into package raft:
# followers that keep receiving pre-vote requests from a partitioned node must
# still time out and elect a new leader. Runs 3 times; every run must pass.
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
# Exit with the verdict for GO_RESULT.
go_verdict() {  # <pass-message> <fail-message>
    case "$GO_RESULT" in
        pass) pass "$1" ;;
        fail) fail "$2" ;;
        skip) fail "the oracle test was skipped" ;;
        *)    go_norun_verdict "$GO_LOG" ;;
    esac
}

ORACLE_FILE="$WORK_DIR/zz_ddbench_oracle_test.go"


rebuild_worktree
[ -f "$WORK_DIR/raft.go" ] || error "hashicorp/raft source not found in $WORK_DIR (run setup first)"
cd "$WORK_DIR"

echo "=== Reproducing raft-609-prevote-contact-liveness ==="

cleanup() { rm -f "$ORACLE_FILE"; }
trap cleanup EXIT

# The oracle test is always injected fresh, under a ddbench-only name and file.
[ -f "$CASE_DIR/inject_test.go" ] || error "oracle test $CASE_DIR/inject_test.go missing"
cp "$CASE_DIR/inject_test.go" "$ORACLE_FILE" || error "could not inject the oracle test"

ORACLE=TestDDBenchOraclePreVoteSpamElection
TOTAL=3
FAILURES=0
for i in $(seq 1 $TOTAL); do
    echo "=== Run $i/$TOTAL ==="
    GO_LOG="$RUN_DIR/run-$i.json"
    INTEG_TESTS=1 timeout 150 go test -json -count=1 -run "^${ORACLE}\$" -timeout 120s . > "$GO_LOG" 2>&1
    GO_RESULT=$(go_test_result "$GO_LOG" "$ORACLE")
    case "$GO_RESULT" in
        pass) echo "  -> OK" ;;
        fail) go_test_transcript "$GO_LOG" | tail -8; echo "  -> FAILED"; FAILURES=$((FAILURES + 1)) ;;
        skip) fail "the oracle test was skipped" ;;
        *)    go_test_transcript "$GO_LOG" | tail -30; go_norun_verdict "$GO_LOG" ;;
    esac
done
[ "$FAILURES" -eq 0 ] && pass "Bug is fixed — a new leader is elected in every run despite pre-vote requests"
fail "Bug is present — followers could not elect a new leader while receiving pre-vote requests ($FAILURES/$TOTAL runs failed)"
