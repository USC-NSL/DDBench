#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6753-populate-sigfpe
# Starts Dragonfly, triggers the bug, and reports PASS/FAIL.
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6753-populate-sigfpe"
BINARY="$WORK_DIR/build-dbg/dragonfly"
PORT=16753
DATA_DIR="$WORK_DIR/dragonfly-6753-data"

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

echo "=== Reproducing dragonfly-6753-populate-sigfpe ==="

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

# Trigger the bug: DEBUG POPULATE with val_size=0
echo "Sending: DEBUG POPULATE 100 prefix 0"
redis-cli -p "$PORT" DEBUG POPULATE 100 prefix 0 2>/dev/null || true
sleep 1

# Check if process crashed
if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo ""
    echo "PASS: Bug is fixed — process survived DEBUG POPULATE with val_size=0"
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
    exit 0
else
    wait "$SERVER_PID" 2>/dev/null
    EXIT_CODE=$?
    echo ""
    echo "FAIL: Bug is present — process crashed (exit code $EXIT_CODE, SIGFPE=136)"
    rm -rf "$DATA_DIR"
    exit 1
fi
