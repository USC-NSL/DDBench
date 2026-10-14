#!/usr/bin/env bash
# Reproduction and verification script for CASE_NAME
# TODO: Brief description of what this script does.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/CASE_NAME"
BINARY="$WORK_DIR/BINARY_PATH"
PORT=TODO_PORT

# ── Rebuild if source changed ──
if [ -f "$WORK_DIR/REBUILD.sh" ] && ! bash "$WORK_DIR/REBUILD.sh"; then
    echo "FAIL: Bug is present — code under test does not build"; exit 1
fi

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 2
fi

# Cleanup from previous runs
# TODO: kill leftover processes, remove temp data
sleep 1

echo "=== Reproducing CASE_NAME ==="

cleanup() {
    # TODO: kill server, remove temp files
    true
}
trap cleanup EXIT

# TODO: Start service (if server-based)

# TODO: Trigger the bug

# TODO: Confirm the trigger actually took effect (fault injected, request delivered,
# node really down, connection really stalled). If not, the run is inconclusive:
#   echo "ERROR: trigger not established (<what was observed>)"; exit 2
# Never let a failed trigger fall through to the verdict, and don't hide trigger
# errors with 2>/dev/null or || true. No sudo: bench.sh reproduce runs as root,
# agents run as the non-root `bench` user. Prefer process-level faults (SIGSTOP,
# kill, a pausable proxy) over iptables/tc.

# TODO: Check outcome
if TODO_BUG_IS_FIXED_CONDITION; then
    echo ""
    echo "PASS: Bug is fixed — TODO_DESCRIPTION"
    exit 0
else
    echo ""
    echo "FAIL: Bug is present — TODO_DESCRIPTION"
    exit 1
fi
