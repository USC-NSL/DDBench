#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6825-config-overflow
# Starts Dragonfly, triggers the bug, and reports PASS/FAIL.
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6825-config-overflow"
BINARY="$WORK_DIR/build-dbg/dragonfly"
PORT=16825
DATA_DIR="$WORK_DIR/dragonfly-6825-data"
NODE_ID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

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

echo "=== Reproducing dragonfly-6825-config-overflow ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
}
trap cleanup EXIT

# Start Dragonfly in cluster mode
"$BINARY" --port "$PORT" --logtostderr --proactor_threads 1 \
    --dbfilename="" --dir "$DATA_DIR" \
    --cluster_mode=yes --cluster_node_id="$NODE_ID" &>/dev/null &
SERVER_PID=$!
sleep 2

# Check server started
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: Dragonfly failed to start."
    exit 1
fi

# Trigger the bug: DFLYCLUSTER CONFIG with overflow value (scientific notation)
# Using 1E383 bypasses JSON integer validation but overflows during parsing
echo "Sending: DFLYCLUSTER CONFIG with overflow value (1E383)"
OVERFLOW_CONFIG='[{"slot_ranges":[{"start":0,"end":1E383}],"master":{"id":"'$NODE_ID'","ip":"127.0.0.1","port":'$PORT'},"replicas":[]}]'
redis-cli -p "$PORT" DFLYCLUSTER CONFIG "$OVERFLOW_CONFIG" 2>/dev/null || true
sleep 1
# Send a follow-up command to trigger the assertion (the crash often happens on the next command after the overflow)
redis-cli -p "$PORT" CLUSTER MYID 2>/dev/null || true
sleep 1

# Check if process crashed
if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo ""
    echo "PASS: Bug is fixed — process survived DFLYCLUSTER CONFIG with overflow value"
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
