#!/usr/bin/env bash
# Reproduction and verification script for CASE_NAME
# Starts the server, sends a trigger, and checks if the process survived.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/CASE_NAME"
BINARY="$WORK_DIR/BINARY_PATH"
PORT=TODO_PORT
DATA_DIR=$(mktemp -d)

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

SERVER_PID=""

cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    rm -rf "$DATA_DIR"
}
trap cleanup EXIT

# Cleanup from previous runs
pkill -f "BINARY_NAME.*--port $PORT" 2>/dev/null || true
sleep 1

echo "=== Reproducing CASE_NAME ==="

# ── Helper: wait for server readiness ──
wait_for_port() {
    local port=$1 timeout=15
    echo "Waiting for server on port $port..."
    for i in $(seq 1 $timeout); do
        # TODO: Adjust readiness check for your server
        if redis-cli -p "$port" PING 2>/dev/null | grep -qi pong; then
            echo "Server is ready."
            return 0
        fi
        sleep 1
    done
    echo "ERROR: Server did not become ready within ${timeout}s."
    return 1
}

# ── Start server ──
echo "Starting server on port $PORT..."
"$BINARY" --port "$PORT" --dir "$DATA_DIR" &>/dev/null &
SERVER_PID=$!
if ! wait_for_port "$PORT"; then exit 1; fi

# ── Trigger the bug ──
echo "Sending trigger..."
# TODO: Send the commands/requests that trigger the crash

sleep 1

# ── Check if process survived ──
if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo ""
    echo "PASS: Bug is fixed — process survived the trigger"
    exit 0
else
    wait "$SERVER_PID" 2>/dev/null
    EXIT_CODE=$?
    echo ""
    echo "FAIL: Bug is present — process crashed (exit code $EXIT_CODE)"
    exit 1
fi
