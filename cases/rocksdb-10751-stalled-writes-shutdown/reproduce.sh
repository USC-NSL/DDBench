#!/usr/bin/env bash
# Reproduction and verification script for rocksdb-10751-stalled-writes-shutdown
# Runs the test binary with a 60-second timeout. If Close() hangs, timeout
# kills the process (exit code 124 = FAIL).
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/rocksdb-10751-stalled-writes-shutdown"
BINARY="$WORK_DIR/test_stall_shutdown"
DB_DIR="$WORK_DIR/testdb"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing rocksdb-10751-stalled-writes-shutdown ==="

cleanup() {
    rm -rf "$DB_DIR"
}
trap cleanup EXIT

# Clean up any previous test database
rm -rf "$DB_DIR"

# Run test with timeout
timeout 60 "$BINARY"
EXIT_CODE=$?

# Clean up test database
rm -rf "$DB_DIR"

echo ""
if [ $EXIT_CODE -eq 124 ]; then
    echo "FAIL: Bug is present — DB::Close() hung for 60+ seconds (killed by timeout)"
    exit 1
elif [ $EXIT_CODE -eq 0 ]; then
    echo "PASS: Bug is fixed — DB::Close() completed normally"
    exit 0
else
    echo "FAIL: Unexpected exit code $EXIT_CODE"
    exit 1
fi
