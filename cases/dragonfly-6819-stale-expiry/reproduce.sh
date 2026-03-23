#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6819-stale-expiry
# Starts Dragonfly, triggers the bug, and reports PASS/FAIL.
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6819-stale-expiry"
BINARY="$WORK_DIR/build-dbg/dragonfly"
PORT=16819
DATA_DIR="$WORK_DIR/dragonfly-6819-data"

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

echo "=== Reproducing dragonfly-6819-stale-expiry ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
}
trap cleanup EXIT

# Start Dragonfly with single proactor thread
"$BINARY" --port "$PORT" --logtostderr --proactor_threads 1 \
    --dbfilename="" --dir "$DATA_DIR" &>/dev/null &
SERVER_PID=$!
sleep 2

# Check server started
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: Dragonfly failed to start."
    exit 1
fi

# Trigger the bug: SET with short expiry, then SORT STORE to overwrite
echo "Sending: SET key val PX 500"
redis-cli -p "$PORT" SET key val PX 500 2>/dev/null || true

echo "Sending: SORT key STORE key"
redis-cli -p "$PORT" SORT key STORE key 2>/dev/null || true

# Wait for the original expiry to fire
echo "Waiting for stale expiry to fire..."
sleep 3

# Check if process crashed
if kill -0 "$SERVER_PID" 2>/dev/null; then
    # Double-check with PING
    if redis-cli -p "$PORT" PING 2>/dev/null | grep -q "PONG"; then
        echo ""
        echo "PASS: Bug is fixed — process survived stale expiry after SORT STORE"
        kill "$SERVER_PID" 2>/dev/null
        wait "$SERVER_PID" 2>/dev/null
        rm -rf "$DATA_DIR"
        exit 0
    fi
fi

wait "$SERVER_PID" 2>/dev/null
EXIT_CODE=$?
echo ""
echo "FAIL: Bug is present — process crashed (exit code $EXIT_CODE)"
rm -rf "$DATA_DIR"
exit 1
