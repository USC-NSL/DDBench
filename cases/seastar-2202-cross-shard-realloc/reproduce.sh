#!/usr/bin/env bash
# Reproduction and verification script for seastar-2202-cross-shard-realloc
# Runs the test binary with --smp 2 and checks for assertion crash.
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/seastar-2202-cross-shard-realloc"
BINARY="$WORK_DIR/test_cross_shard_realloc"

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
