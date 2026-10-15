#!/usr/bin/env bash
# Reproduction and verification script for <case-name>
# TODO: one or two lines on what this oracle does, in observable terms (the scenario
# and what is checked), never the root-cause mechanism or the fix.
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

# Generic skeleton. Prefer a bug-type-specific template (see templates/README.md)
# when one fits.

BINARY="$WORK_DIR/BINARY_PATH"
PORT=TODO_PORT
DATA_DIR="$RUN_DIR/data"          # scratch data lives in $RUN_DIR, never in the worktree
SERVER_PID=""

cleanup() {
    # TODO: stop every process this script started and remove anything it wrote
    # into the worktree (injected tests, reports, binaries built from them).
    if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; fi
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

rebuild_worktree
[ -x "$BINARY" ] || error "binary not found at $BINARY (run setup first)"
mkdir -p "$DATA_DIR"

echo "=== Reproducing <case-name> ==="

# TODO: Start the service (if server-based). If the code under test does not start,
# that is FAIL, e.g.: fail "the server did not start serving"

# TODO: Trigger the bug, with bounded client calls (timeout 5 redis-cli ...).

# TODO: Confirm the trigger actually took effect (fault injected, request delivered,
# node really down, connection really stalled). If not, the run is inconclusive:
#   error "trigger not established (<what was observed>)"
# Never let a failed trigger fall through to the verdict, and don't hide trigger
# errors with 2>/dev/null or || true. No sudo (the images ship none; this container
# runs as root). Prefer process-level faults (SIGSTOP, kill, a pausable proxy) over
# iptables/tc. Nothing may be downloaded here: scoring runs with --network none.

# TODO: Observe the behavior the fix changes and decide. Judge from structured
# output (exit status, a protocol reply, a test report), never from free text the
# code under test could print.
if TODO_BUG_IS_FIXED_CONDITION; then
    pass "Bug is fixed — TODO_DESCRIPTION"
fi
fail "Bug is present — TODO_DESCRIPTION"
