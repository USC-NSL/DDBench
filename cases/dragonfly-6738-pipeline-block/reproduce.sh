#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6738-pipeline-block
# Starts Dragonfly, sends a pipeline with blocking command, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6738-pipeline-block"
BINARY="$WORK_DIR/build-dbg/dragonfly"
PORT=16738
DATA_DIR="$WORK_DIR/dragonfly-6738-data"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

# Cleanup from previous runs
pkill -f "dragonfly.*--port $PORT" 2>/dev/null || true
sleep 1
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"

echo "=== Reproducing dragonfly-6738-pipeline-block ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
}
trap cleanup EXIT

# Start Dragonfly
"$BINARY" --port "$PORT" --logtostderr --proactor_threads 2 \
    --dbfilename="" --dir "$DATA_DIR" &>/dev/null &
SERVER_PID=$!
sleep 2

# Check server started
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: Dragonfly failed to start."
    exit 1
fi

# Send pipeline: SET + PING + BLPOP (BLPOP on nonexistent list with 5s timeout)
# With the bug, SET and PING replies are held back until BLPOP times out (~5s)
echo "Sending pipeline: SET mykey myval | PING | BLPOP nolist 5"
START=$(date +%s)
printf "SET mykey myval\r\nPING\r\nBLPOP nolist 5\r\n" | redis-cli -p "$PORT" --pipe-timeout 10 >/dev/null 2>&1
END=$(date +%s)
ELAPSED=$((END - START))

# Cleanup
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null
rm -rf "$DATA_DIR"

# Report result
if [ "$ELAPSED" -ge "4" ]; then
    echo ""
    echo "FAIL: Bug is present — pipeline replies delayed ${ELAPSED}s by BLPOP"
    exit 1
else
    echo ""
    echo "PASS: Bug is fixed — pipeline replies returned promptly (${ELAPSED}s)"
    exit 0
fi
