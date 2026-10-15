#!/usr/bin/env bash
# Reproduction and verification script for etcd-19172-embed-data-race
# Runs the existing TestEmbedEtcd* integration tests (tests/integration/embed)
# under the Go race detector: 10 invocations of -count=3 (30 executions; the
# race shows up in roughly 1 of 5 executions). A data race in any run is FAIL;
# PASS requires the tests to actually run and pass in every run.
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


rebuild_worktree
[ -d "$WORK_DIR/server" ] || error "etcd source not found in $WORK_DIR (run setup first)"

echo "=== Reproducing etcd-19172-embed-data-race ==="

cleanup() { pkill -f "etcd --name" 2>/dev/null || true; }
trap cleanup EXIT
cd "$WORK_DIR/tests/integration/embed" || error "tests/integration/embed not found"

for i in $(seq 1 10); do
    echo "=== Run $i/10 (-race) ==="
    GO_LOG="$RUN_DIR/race-$i.json"
    go test -json -race -run '^TestEmbedEtcd' -count=3 -timeout 300s . > "$GO_LOG" 2>&1
    if grep -q 'WARNING: DATA RACE' "$GO_LOG"; then
        go_test_transcript "$GO_LOG" | grep -A 20 'DATA RACE' | head -30
        fail "Bug is present — data race detected in run $i"
    fi
    # Every top-level TestEmbedEtcd* test that ran must have passed, and at
    # least one must have run.
    ran=$(grep -cE '^\{("Time":"[^"]*",)?"Action":"pass","Package":"[^"]*","Test":"TestEmbedEtcd[^"/]*"' "$GO_LOG")
    if grep -qE '^\{("Time":"[^"]*",)?"Action":"fail","Package":"[^"]*","Test":"TestEmbedEtcd' "$GO_LOG"; then
        go_test_transcript "$GO_LOG" | tail -40
        fail "a TestEmbedEtcd test failed in run $i"
    fi
    if [ "$ran" -eq 0 ]; then
        go_test_transcript "$GO_LOG" | tail -40
        go_norun_verdict "$GO_LOG"
    fi
    echo "Run $i: $ran TestEmbedEtcd test(s) passed, no race detected"
done
pass "Bug is fixed — no data race detected in 10 race-detector runs (-count=3 each)"
