#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6819-stale-expiry
# Starts Dragonfly, triggers the bug, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
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

# Trigger the bug: LPUSH a list with short expiry, then SORT STORE to overwrite
echo "Sending: LPUSH mylist 3 2 1"
redis-cli -p "$PORT" LPUSH mylist 3 2 1 2>/dev/null || true

echo "Sending: PEXPIRE mylist 500"
redis-cli -p "$PORT" PEXPIRE mylist 500 2>/dev/null || true

echo "Sending: SORT mylist STORE mylist"
redis-cli -p "$PORT" SORT mylist STORE mylist 2>/dev/null || true

# Wait for the original expiry to fire
echo "Waiting for stale expiry to fire..."
sleep 1

echo "Sending: PING"
redis-cli -p "$PORT" PING 2>/dev/null || true
sleep 2

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
