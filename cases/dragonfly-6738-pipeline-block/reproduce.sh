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
# With the bug, SET and PING replies are held back until BLPOP times out (~5s).
# We measure the arrival time of the FIRST reply bytes, not total pipeline time:
# total time is gated by BLPOP's 5s timeout regardless of the bug, so it cannot
# discriminate; but the arrival time of the SET reply is ~0s when fixed and ~5s
# when buggy.
echo "Sending pipeline: SET mykey myval | PING | BLPOP nolist 5"
FIRST_REPLY_T=$(python3 - "$PORT" <<'PY'
import socket, sys, time
port = int(sys.argv[1])
s = socket.socket()
s.settimeout(10)
s.connect(('127.0.0.1', port))
msg = b"SET mykey myval\r\nPING\r\nBLPOP nolist 5\r\n"
t0 = time.time()
s.sendall(msg)
chunk = s.recv(4096)  # blocks until the first reply bytes arrive
t1 = time.time()
if not chunk:
    print("nan")
else:
    print(f"{t1 - t0:.3f}")
PY
)

# Cleanup
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null
rm -rf "$DATA_DIR"

# Report result: first reply should arrive in well under 2s when fixed; when
# buggy it is held back until BLPOP's 5s timeout.
if [ -z "$FIRST_REPLY_T" ] || [ "$FIRST_REPLY_T" = "nan" ]; then
    echo ""
    echo "FAIL: Could not read any reply from server"
    exit 1
fi
if awk -v t="$FIRST_REPLY_T" 'BEGIN{ exit !(t+0 >= 2.0) }'; then
    echo ""
    echo "FAIL: Bug is present — first reply delayed ${FIRST_REPLY_T}s (held until BLPOP timeout)"
    exit 1
else
    echo ""
    echo "PASS: Bug is fixed — first reply returned promptly (${FIRST_REPLY_T}s)"
    exit 0
fi
