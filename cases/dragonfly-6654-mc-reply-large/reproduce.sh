#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6654-mc-reply-large
# Starts Dragonfly, triggers the bug, and reports PASS/FAIL.
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6654-mc-reply-large"
BINARY="$WORK_DIR/build-dbg/dragonfly"
PORT=16654
MC_PORT=11211
DATA_DIR="$WORK_DIR/dragonfly-6654-data"

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

echo "=== Reproducing dragonfly-6654-mc-reply-large ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
}
trap cleanup EXIT

# Start Dragonfly with memcached port and large bulk length
"$BINARY" --port "$PORT" --memcached_port="$MC_PORT" --max_bulk_len=1048576 \
    --logtostderr --proactor_threads 1 --dbfilename="" --dir "$DATA_DIR" &>/dev/null &
SERVER_PID=$!
sleep 2

# Check server started
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: Dragonfly failed to start."
    exit 1
fi

# Trigger the bug: SET an 8000+ byte value, then retrieve via memcached meta get
echo "Sending: SET bigkey with 8000-byte value via Redis, then meta get via memcached"
LARGE_VALUE=$(python3 -c "print('A' * 8000)")
redis-cli -p "$PORT" SET bigkey "$LARGE_VALUE" >/dev/null 2>&1

# Retrieve via memcached meta get — this triggers the crash
echo -e "mg bigkey v\r\nquit\r\n" | nc -q 2 127.0.0.1 "$MC_PORT" >/dev/null 2>&1 || true
sleep 1

# Check if process crashed
if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo ""
    echo "PASS: Bug is fixed — process survived memcached meta get on large value"
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
    exit 0
else
    wait "$SERVER_PID" 2>/dev/null
    EXIT_CODE=$?
    echo ""
    echo "FAIL: Bug is present — process crashed (exit code $EXIT_CODE, SIGABRT=134)"
    rm -rf "$DATA_DIR"
    exit 1
fi
