#!/usr/bin/env bash
# Reproduction and verification script for raft-268-shutdown-deadlock
# Runs the test binary 20 times and counts deadlocks (timeout = deadlock).
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/raft-268-shutdown-deadlock"
BINARY="$WORK_DIR/test/raft-deadlock-test"
export PATH="$PATH:/usr/local/go/bin"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing raft-268-shutdown-deadlock ==="

cleanup() {
    pkill -f "raft-deadlock-test" 2>/dev/null || true
}
trap cleanup EXIT

FAILURES=0
TOTAL=50

for i in $(seq 1 $TOTAL); do
    timeout 15 "$BINARY" > /dev/null 2>&1
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        FAILURES=$((FAILURES + 1))
        echo "Attempt $i: DEADLOCK (exit code $EXIT_CODE)"
    else
        echo "Attempt $i: OK"
    fi
done

echo ""
if [ $FAILURES -gt 0 ]; then
    echo "FAIL: Bug is present — $FAILURES/$TOTAL runs deadlocked"
    exit 1
else
    echo "PASS: Bug is fixed — all $TOTAL runs completed without deadlock"
    exit 0
fi
