#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6909-search-nonfinite
# Starts Dragonfly, triggers the bug, and reports PASS/FAIL.
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6909-search-nonfinite"
BINARY="$WORK_DIR/build-dbg/dragonfly"
PORT=16909
DATA_DIR="$WORK_DIR/dragonfly-6909-data"

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

echo "=== Reproducing dragonfly-6909-search-nonfinite ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
}
trap cleanup EXIT

# Start Dragonfly
"$BINARY" --port "$PORT" --logtostderr --proactor_threads 1 \
    --dbfilename="" --dir "$DATA_DIR" &>/dev/null &
SERVER_PID=$!
sleep 2

# Check server started
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: Dragonfly failed to start."
    exit 1
fi

# Trigger the bug: FT.CREATE with numeric index, HSET score inf
echo "Sending: FT.CREATE myidx ON HASH PREFIX 1 doc: SCHEMA score NUMERIC"
redis-cli -p "$PORT" FT.CREATE myidx ON HASH PREFIX 1 doc: SCHEMA score NUMERIC 2>/dev/null || true

echo "Sending: HSET doc:1 score inf"
redis-cli -p "$PORT" HSET doc:1 score inf 2>/dev/null || true
sleep 0.5

echo "Sending: FT.SEARCH myidx '*'"
redis-cli -p "$PORT" FT.SEARCH myidx '*' 2>/dev/null || true
sleep 1

# Check if process crashed
if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo ""
    echo "PASS: Bug is fixed — process survived FT.SEARCH with non-finite numeric value"
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
    exit 0
else
    wait "$SERVER_PID" 2>/dev/null
    EXIT_CODE=$?
    echo ""
    echo "FAIL: Bug is present — process crashed (exit code $EXIT_CODE)"
    rm -rf "$DATA_DIR"
    exit 1
fi
