#!/usr/bin/env bash
# Reproduction and verification script for raft-268-shutdown-deadlock
# The test binary internally runs 50 attempts and exits 1 on first deadlock.
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

# The binary runs 50 internal attempts.
# Exit 1 = bug present (deadlock detected), Exit 0 = bug absent.
timeout 600 "$BINARY"
exit $?
