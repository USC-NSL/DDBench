#!/usr/bin/env bash
# Reproduction and verification script for seastar-2202-cross-shard-realloc
# Runs the test binary with --smp 2 and checks for assertion crash.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/seastar-2202-cross-shard-realloc"
BINARY="$WORK_DIR/test_cross_shard_realloc"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing seastar-2202-cross-shard-realloc ==="

cleanup() {
    pkill -f "test_cross_shard_realloc" 2>/dev/null || true
}
trap cleanup EXIT

# Set LD_LIBRARY_PATH for Seastar shared libraries
export LD_LIBRARY_PATH="$WORK_DIR/build/dev:$WORK_DIR/build/dev/_cooking/stow/fmt/lib:$WORK_DIR/build/dev/_cooking/installed/lib:${LD_LIBRARY_PATH:-}"

# Run with 2 shards to enable cross-shard allocation
"$BINARY" --smp 2 2>&1
EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "PASS: Bug is fixed — cross-shard realloc shrink succeeded"
    exit 0
elif [ $EXIT_CODE -eq 134 ]; then
    echo "FAIL: Bug is present — assertion 'object_cpu_id(ptr) == cpu_id' failed (exit code 134 / SIGABRT)"
    exit 1
else
    echo "FAIL: Bug is present — process crashed (exit code $EXIT_CODE)"
    exit 1
fi
