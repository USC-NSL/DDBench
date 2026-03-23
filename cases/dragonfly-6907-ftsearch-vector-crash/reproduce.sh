#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6907-ftsearch-vector-crash
# Starts Dragonfly, triggers the bug, and reports PASS/FAIL.
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6907-ftsearch-vector-crash"
BINARY="$WORK_DIR/build-dbg/dragonfly"
PORT=16907
DATA_DIR="$WORK_DIR/dragonfly-6907-data"

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

echo "=== Reproducing dragonfly-6907-ftsearch-vector-crash ==="

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

# Trigger the bug using python3 redis client to send binary vector data
echo "Creating vector index and inserting wrong-sized vector via Python"
python3 -c "
import redis
import struct

r = redis.Redis(host='127.0.0.1', port=$PORT)

# Create index expecting 4-dim FLOAT32 vector (16 bytes)
r.execute_command('FT.CREATE', 'idx', 'ON', 'HASH', 'PREFIX', '1', 'doc:',
                  'SCHEMA', 'vec', 'VECTOR', 'FLAT', '6',
                  'TYPE', 'FLOAT32', 'DIM', '4', 'DISTANCE_METRIC', 'L2')

# Insert doc with wrong size: 2 dims (8 bytes) instead of 4 dims (16 bytes)
wrong_vec = struct.pack('ff', 1.0, 2.0)
r.hset('doc:1', 'vec', wrong_vec)

# Search triggers the crash
try:
    r.execute_command('FT.SEARCH', 'idx', '*')
except Exception:
    pass
" 2>/dev/null || true
sleep 1

# Check if process crashed
if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo ""
    echo "PASS: Bug is fixed — process survived FT.SEARCH with wrong-sized vector"
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
