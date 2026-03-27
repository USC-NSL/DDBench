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
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
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
