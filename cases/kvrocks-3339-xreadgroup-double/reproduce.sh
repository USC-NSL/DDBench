#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-3339-xreadgroup-double
# Starts Kvrocks, triggers the bug via concurrent XREADGROUP BLOCK + XADD,
# and detects the protocol-level double response.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-3339-xreadgroup-double"
BINARY="$WORK_DIR/build/kvrocks"
PORT=13339
DATA_DIR="$WORK_DIR/kvrocks-3339-data"
DETECT_SCRIPT="$WORK_DIR/kvrocks-3339-detect.py"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

# Cleanup from previous runs
pkill -f "kvrocks.*--port $PORT" 2>/dev/null || true
sleep 1
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"

echo "=== Reproducing kvrocks-3339-xreadgroup-double ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
    rm -f "$DETECT_SCRIPT"
    rm -f "$WORK_DIR"/kvrocks-3339-consumer_*.out
}
trap cleanup EXIT

# Start Kvrocks
"$BINARY" --port "$PORT" --dir "$DATA_DIR" --log-dir "$DATA_DIR" &>/dev/null &
SERVER_PID=$!
sleep 2

# Check server started
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: Kvrocks failed to start."
    exit 1
fi

# Write the Python detection script that uses raw sockets to detect double RESP responses
cat > "$DETECT_SCRIPT" <<'PYEOF'
import socket
import threading
import time
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 13339
NUM_CONSUMERS = 5
NUM_ROUNDS = 20
NUM_PRODUCE = 100
DOUBLE_RESP_DETECTED = threading.Event()
errors = []

def send_redis_cmd(sock, *args):
    """Send a RESP command over a raw socket."""
    cmd = f"*{len(args)}\r\n"
    for a in args:
        a = str(a)
        cmd += f"${len(a)}\r\n{a}\r\n"
    sock.sendall(cmd.encode())

def recv_all(sock, timeout=3.0):
    """Receive all available data from socket within timeout."""
    sock.settimeout(timeout)
    data = b""
    try:
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                break
            data += chunk
    except socket.timeout:
        pass
    return data

def consumer_thread(consumer_id):
    """Open a raw socket, send XREADGROUP BLOCK, check for double responses."""
    try:
        for round_num in range(NUM_ROUNDS):
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.connect(("127.0.0.1", PORT))
            # Send XREADGROUP GROUP mygroup consumerN BLOCK 2000 COUNT 1 STREAMS teststream >
            send_redis_cmd(sock, "XREADGROUP", "GROUP", "mygroup",
                           f"consumer{consumer_id}", "BLOCK", "2000",
                           "COUNT", "1", "STREAMS", "teststream", ">")
            # Wait for response
            resp = recv_all(sock, timeout=3.0)
            resp_text = resp.decode("utf-8", errors="replace")
            # Check for double response: look for two RESP top-level replies
            # A double response would contain patterns like *-1\r\n followed by another * or $
            # or two complete RESP arrays
            parts = resp_text.split("\r\n")
            top_level_count = 0
            for p in parts:
                if p and (p[0] in ('*', '+', '-', ':', '$')):
                    top_level_count += 1
            # A single XREADGROUP response has one top-level * marker
            # followed by nested arrays. If we see *-1 followed by another *,
            # that's a double response.
            if "*-1" in resp_text and resp_text.count("*-1") < resp_text.count("*"):
                # Potential double response: nil array followed by actual data
                idx = resp_text.find("*-1")
                after = resp_text[idx+5:]  # skip past *-1\r\n
                if after.strip():
                    errors.append(f"consumer{consumer_id} round {round_num}: double response detected")
                    DOUBLE_RESP_DETECTED.set()
            sock.close()
    except Exception as e:
        errors.append(f"consumer{consumer_id}: {e}")

def producer_thread():
    """Rapidly add entries to the stream."""
    time.sleep(0.5)
    for i in range(NUM_PRODUCE):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.connect(("127.0.0.1", PORT))
            send_redis_cmd(sock, "XADD", "teststream", "*", "key", f"value{i}")
            recv_all(sock, timeout=1.0)
            sock.close()
        except Exception:
            pass
        time.sleep(0.005)

# Setup: create stream and consumer group
setup_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
setup_sock.connect(("127.0.0.1", PORT))
send_redis_cmd(setup_sock, "DEL", "teststream")
recv_all(setup_sock, timeout=1.0)
setup_sock.close()

setup_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
setup_sock.connect(("127.0.0.1", PORT))
send_redis_cmd(setup_sock, "XADD", "teststream", "*", "init", "init")
recv_all(setup_sock, timeout=1.0)
setup_sock.close()

setup_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
setup_sock.connect(("127.0.0.1", PORT))
send_redis_cmd(setup_sock, "XGROUP", "CREATE", "teststream", "mygroup", "0")
recv_all(setup_sock, timeout=1.0)
setup_sock.close()

# Run consumers and producer concurrently
threads = []
for i in range(NUM_CONSUMERS):
    t = threading.Thread(target=consumer_thread, args=(i,))
    threads.append(t)
    t.start()

pt = threading.Thread(target=producer_thread)
pt.start()

pt.join()
for t in threads:
    t.join(timeout=30)

if errors:
    print(f"DOUBLE_RESPONSE_ERRORS={len(errors)}")
    for e in errors[:5]:
        print(f"  {e}")
else:
    print("DOUBLE_RESPONSE_ERRORS=0")
PYEOF

# Run the detection script
echo "Running double-response detection (raw socket approach)..."
DETECT_OUTPUT=$(python3 "$DETECT_SCRIPT" "$PORT" 2>&1)
echo "$DETECT_OUTPUT"

# Also run the redis-cli based approach as a fallback check
echo ""
echo "Running redis-cli consumer-based check..."
CONSUMER_ERRORS=0
for i in $(seq 1 5); do
    (for j in $(seq 1 20); do
        redis-cli -p "$PORT" XREADGROUP GROUP mygroup "cli_consumer$i" BLOCK 1000 COUNT 1 STREAMS teststream '>' 2>&1
    done) > "$WORK_DIR/kvrocks-3339-consumer_$i.out" 2>&1 &
done

sleep 0.5

# Producer: rapid XADD
for i in $(seq 1 100); do
    redis-cli -p "$PORT" XADD teststream '*' key "value_cli_$i" >/dev/null 2>&1
done

# Wait for consumers to finish
sleep 5
wait 2>/dev/null

for i in $(seq 1 5); do
    if grep -qi "error\|ERR\|WRONGTYPE\|invalid" "$WORK_DIR/kvrocks-3339-consumer_$i.out" 2>/dev/null; then
        CONSUMER_ERRORS=$((CONSUMER_ERRORS + 1))
    fi
done

# Cleanup
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null
rm -rf "$DATA_DIR"
rm -f "$DETECT_SCRIPT"
rm -f "$WORK_DIR/kvrocks-3339-consumer_*.out"

# Parse results from Python script
DOUBLE_COUNT=$(echo "$DETECT_OUTPUT" | grep "DOUBLE_RESPONSE_ERRORS=" | head -1 | cut -d= -f2)
DOUBLE_COUNT=${DOUBLE_COUNT:-0}

if [ "$DOUBLE_COUNT" -gt 0 ] || [ "$CONSUMER_ERRORS" -gt 0 ]; then
    echo ""
    echo "FAIL: Bug is present — double RESP responses detected (raw_socket=$DOUBLE_COUNT, cli_errors=$CONSUMER_ERRORS)"
    exit 1
else
    echo ""
    echo "PASS: Bug is fixed — all consumers received single responses per command"
    exit 0
fi
