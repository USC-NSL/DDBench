#!/usr/bin/env bash
# Reproduction and verification script for raft-268-shutdown-deadlock
# Builds the canonical harness (test_main.go, shipped with this case and never
# placed in the worktree) against the worktree's hashicorp/raft and runs it: 50
# attempts of shutting down a single-node cluster while an FSM snapshot is in
# flight. A Shutdown() that does not return within 10s is the bug.
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


rebuild_worktree
[ -f "$WORK_DIR/raft.go" ] || error "hashicorp/raft source not found in $WORK_DIR (run setup first)"
[ -f "$CASE_DIR/test_main.go" ] || error "harness $CASE_DIR/test_main.go missing"

echo "=== Reproducing raft-268-shutdown-deadlock ==="

# Build the pristine harness outside the agent-editable worktree.
HARNESS_DIR="$RUN_DIR/harness"
mkdir -p "$HARNESS_DIR"
cp "$CASE_DIR/test_main.go" "$HARNESS_DIR/main.go"
cat > "$HARNESS_DIR/go.mod" << EOF
module ddbench-raft-shutdown-harness

go 1.21

replace github.com/hashicorp/raft => $WORK_DIR
EOF
cd "$HARNESS_DIR"
if ! go mod tidy > "$RUN_DIR/tidy.log" 2>&1; then
    cat "$RUN_DIR/tidy.log"
    if grep -qE 'dial tcp|i/o timeout|TLS handshake timeout|no such host' "$RUN_DIR/tidy.log"; then
        error "could not download the harness's Go modules (network)"
    fi
    fail "the worktree's Go module cannot be resolved for the harness (go mod tidy failed)"
fi
if ! go build -o "$RUN_DIR/raft-shutdown-harness" . > "$RUN_DIR/build.log" 2>&1; then
    cat "$RUN_DIR/build.log"
    fail "the harness does not compile against the worktree's raft package"
fi

# The harness prints its own PASS/FAIL/ERROR line and follows the exit-code
# contract (0 PASS, 1 FAIL, 2 ERROR).
timeout 900 "$RUN_DIR/raft-shutdown-harness"
rc=$?
case "$rc" in
    0|1|2) exit "$rc" ;;
    124)   fail "Bug is present — the harness hung for 900s" ;;
    *)     error "the harness terminated unexpectedly (exit $rc)" ;;
esac
