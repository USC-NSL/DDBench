#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-3356-replication-wal
# Starts Kvrocks master + replica, throttles replica via iptables,
# generates write load, and checks WAL growth. Reports PASS/FAIL.
# NOTE: Requires sudo for iptables rules.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-3356-replication-wal"
BINARY="$WORK_DIR/build/kvrocks"
MASTER_PORT=13356
REPLICA_PORT=13357
MASTER_DIR="$WORK_DIR/kvrocks-3356-master"
REPLICA_DIR="$WORK_DIR/kvrocks-3356-replica"
MASTER_CONF="$WORK_DIR/kvrocks-3356-master.conf"
REPLICA_CONF="$WORK_DIR/kvrocks-3356-replica.conf"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

# Cleanup function to ensure iptables rule is always removed
cleanup() {
    echo "Cleaning up..."
    sudo iptables -D OUTPUT -p tcp --dport "$REPLICA_PORT" -m statistic --mode random --probability 0.9 -j DROP 2>/dev/null || true
    kill "$MASTER_PID" 2>/dev/null || true
    kill "$REPLICA_PID" 2>/dev/null || true
    wait "$MASTER_PID" 2>/dev/null || true
    wait "$REPLICA_PID" 2>/dev/null || true
    rm -rf "$MASTER_DIR" "$REPLICA_DIR"
    rm -f "$MASTER_CONF" "$REPLICA_CONF"
}
trap cleanup EXIT

# Cleanup from previous runs
pkill -f "kvrocks.*--port $MASTER_PORT" 2>/dev/null || true
pkill -f "kvrocks.*--port $REPLICA_PORT" 2>/dev/null || true
pkill -f "kvrocks.*-c $MASTER_CONF" 2>/dev/null || true
pkill -f "kvrocks.*-c $REPLICA_CONF" 2>/dev/null || true
sudo iptables -D OUTPUT -p tcp --dport "$REPLICA_PORT" -m statistic --mode random --probability 0.9 -j DROP 2>/dev/null || true
sleep 1
rm -rf "$MASTER_DIR" "$REPLICA_DIR"
mkdir -p "$MASTER_DIR" "$REPLICA_DIR"

echo "=== Reproducing kvrocks-3356-replication-wal ==="

# Create master config
cat > "$MASTER_CONF" <<EOF
bind 0.0.0.0
port $MASTER_PORT
dir $MASTER_DIR
log-dir $MASTER_DIR
EOF

# Create replica config
cat > "$REPLICA_CONF" <<EOF
bind 0.0.0.0
port $REPLICA_PORT
dir $REPLICA_DIR
log-dir $REPLICA_DIR
slaveof 127.0.0.1 $MASTER_PORT
EOF

# Start master
echo "Starting master on port $MASTER_PORT..."
"$BINARY" -c "$MASTER_CONF" &>/dev/null &
MASTER_PID=$!
sleep 2

if ! kill -0 "$MASTER_PID" 2>/dev/null; then
    echo "ERROR: Master failed to start."
    exit 1
fi

# Start replica
echo "Starting replica on port $REPLICA_PORT..."
"$BINARY" -c "$REPLICA_CONF" &>/dev/null &
REPLICA_PID=$!
sleep 3

if ! kill -0 "$REPLICA_PID" 2>/dev/null; then
    echo "ERROR: Replica failed to start."
    exit 1
fi

# Verify replication is working
echo "Checking replication status..."
REPL_INFO=$(redis-cli -p "$MASTER_PORT" INFO replication 2>/dev/null)
if ! echo "$REPL_INFO" | grep -q "connected_slaves:1"; then
    echo "WARNING: Replica may not be connected yet, continuing anyway..."
fi
echo "$REPL_INFO" | grep -E "connected_slaves|slave0" || true

# Record initial WAL size
INITIAL_SIZE=$(du -s "$MASTER_DIR" 2>/dev/null | awk '{print $1}')
echo "Initial master dir size: ${INITIAL_SIZE}KB"

# Throttle replica via iptables (drop 90% of packets to replica port)
echo "Applying iptables rule to throttle replica (drop 90% of packets to port $REPLICA_PORT)..."
sudo iptables -A OUTPUT -p tcp --dport "$REPLICA_PORT" -m statistic --mode random --probability 0.9 -j DROP

# Generate high write load on master
echo "Running redis-benchmark (1M SET operations, 256-byte values, 50 clients, pipeline 32)..."
redis-benchmark -p "$MASTER_PORT" -t set -n 1000000 -r 1000000 -d 256 -c 50 -P 32 -q 2>/dev/null

# Wait for WAL to accumulate
echo "Waiting 10 seconds for WAL accumulation..."
sleep 10

# Check WAL size after load
FINAL_SIZE=$(du -s "$MASTER_DIR" 2>/dev/null | awk '{print $1}')
GROWTH=$((FINAL_SIZE - INITIAL_SIZE))
echo "Final master dir size: ${FINAL_SIZE}KB"
echo "WAL growth: ${GROWTH}KB"

# WAL growth > 512MB (512000KB) indicates unbounded growth (bug present)
if [ "$GROWTH" -gt 512000 ]; then
    echo ""
    echo "FAIL: Bug is present — WAL grew by ${GROWTH}KB (> 512MB, unbounded growth)"
    exit 1
else
    echo ""
    echo "PASS: Bug is fixed — WAL growth bounded at ${GROWTH}KB (< 512MB)"
    exit 0
fi
