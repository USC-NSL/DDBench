#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6614-monitor-multiexec
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
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6614-monitor-multiexec"
BINARY="$WORK_DIR/build-dbg/dragonfly"
PORT=16614
DATA_DIR="$WORK_DIR/dragonfly-6614-data"

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

echo "=== Reproducing dragonfly-6614-monitor-multiexec ==="

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

# Trigger the bug: MULTI, MONITOR, MONITOR, EXEC in pipeline with concurrent connections
echo "Sending: 100 rounds of 10 concurrent MULTI+MONITOR+EXEC pipelines"
python3 -c "
import socket, threading, time

def attempt(port):
    try:
        s = socket.socket()
        s.settimeout(2)
        s.connect(('127.0.0.1', port))
        s.sendall(b'*1\r\n\$5\r\nMULTI\r\n*1\r\n\$7\r\nMONITOR\r\n*1\r\n\$7\r\nMONITOR\r\n*1\r\n\$4\r\nEXEC\r\n')
        time.sleep(0.1)
        s.close()
    except:
        pass

PORT = $PORT
for _ in range(100):
    threads = [threading.Thread(target=attempt, args=(PORT,)) for _ in range(10)]
    for t in threads: t.start()
    for t in threads: t.join()
" 2>/dev/null || true
sleep 1

# Send another command to trigger the crash on the closed connection
redis-cli -p "$PORT" PING >/dev/null 2>&1 || true
sleep 1

# Check if process crashed
if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo ""
    echo "PASS: Bug is fixed — process survived MONITOR inside MULTI/EXEC"
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
