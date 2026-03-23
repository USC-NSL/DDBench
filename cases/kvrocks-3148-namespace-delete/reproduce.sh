#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-3148-namespace-delete
# Starts Kvrocks, triggers the bug, and reports PASS/FAIL.
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-3148-namespace-delete"
BINARY="$WORK_DIR/build/kvrocks"
PORT=13148
DATA_DIR="$WORK_DIR/kvrocks-3148-data"
CONF_FILE="$WORK_DIR/kvrocks-3148.conf"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

# Cleanup from previous runs
pkill -f "kvrocks.*--port $PORT" 2>/dev/null || true
pkill -f "kvrocks.*-c $CONF_FILE" 2>/dev/null || true
sleep 1
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR/logs"

echo "=== Reproducing kvrocks-3148-namespace-delete ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
    rm -f "$CONF_FILE"
}
trap cleanup EXIT

# Create config file with requirepass (needed for NAMESPACE commands)
cat > "$CONF_FILE" <<EOF
bind 0.0.0.0
port $PORT
dir $DATA_DIR
log-dir $DATA_DIR/logs
requirepass foobared
EOF

# Start Kvrocks
"$BINARY" -c "$CONF_FILE" &>/dev/null &
SERVER_PID=$!
sleep 2

# Check server started
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: Kvrocks failed to start."
    rm -f "$CONF_FILE"
    exit 1
fi

# Create two namespaces with different tokens
echo "Adding namespace ns1 with token1..."
redis-cli -p "$PORT" -a foobared NAMESPACE ADD ns1 token1 2>/dev/null
echo "Adding namespace ns2 with token2..."
redis-cli -p "$PORT" -a foobared NAMESPACE ADD ns2 token2 2>/dev/null

echo "Current namespaces:"
redis-cli -p "$PORT" -a foobared NAMESPACE GET '*' 2>/dev/null

# Trigger the bug: set ns1's token to ns2's token (duplicate)
echo ""
echo "Sending: NAMESPACE SET ns1 token2 (duplicate token)"
redis-cli -p "$PORT" -a foobared NAMESPACE SET ns1 token2 2>/dev/null

# Check if ns2 still exists
echo ""
echo "Checking namespaces after SET:"
RESULT=$(redis-cli -p "$PORT" -a foobared NAMESPACE GET '*' 2>/dev/null)
echo "$RESULT"

# Cleanup
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null
rm -rf "$DATA_DIR"
rm -f "$CONF_FILE"

# Verdict
if echo "$RESULT" | grep -q "ns2"; then
    echo ""
    echo "PASS: Bug is fixed — ns2 still exists after token collision"
    exit 0
else
    echo ""
    echo "FAIL: Bug is present — ns2 was deleted when ns1 took its token"
    exit 1
fi
