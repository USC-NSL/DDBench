#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-3208-replication-watermark
# Starts master + replica, writes a large value then a small value,
# and checks whether the small value replicates promptly. Reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-3208-replication-watermark"
BINARY="$WORK_DIR/build/kvrocks"
MASTER_PORT=13208
REPLICA_PORT=13209
MASTER_DIR="$WORK_DIR/kvrocks-3208-master"
REPLICA_DIR="$WORK_DIR/kvrocks-3208-replica"
MASTER_CONF="$WORK_DIR/kvrocks-3208-master.conf"
REPLICA_CONF="$WORK_DIR/kvrocks-3208-replica.conf"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

cleanup() {
    echo "Cleaning up..."
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
sleep 1
rm -rf "$MASTER_DIR" "$REPLICA_DIR"
mkdir -p "$MASTER_DIR" "$REPLICA_DIR"

echo "=== Reproducing kvrocks-3208-replication-watermark ==="

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

# Wait for master to be ready
echo "Waiting for master to be ready..."
for i in $(seq 1 30); do
    if redis-cli -p "$MASTER_PORT" PING 2>/dev/null | grep -q PONG; then
        break
    fi
    sleep 0.5
done

if ! kill -0 "$MASTER_PID" 2>/dev/null; then
    echo "ERROR: Master failed to start."
    exit 1
fi

# Start replica
echo "Starting replica on port $REPLICA_PORT..."
"$BINARY" -c "$REPLICA_CONF" &>/dev/null &
REPLICA_PID=$!

# Wait for replica to complete full sync
echo "Waiting for replica to complete full sync..."
for i in $(seq 1 60); do
    LINK_STATUS=$(redis-cli -p "$REPLICA_PORT" INFO replication 2>/dev/null | grep master_link_status | tr -d '\r')
    if echo "$LINK_STATUS" | grep -q "up"; then
        break
    fi
    sleep 0.5
done

if ! kill -0 "$REPLICA_PID" 2>/dev/null; then
    echo "ERROR: Replica failed to start."
    exit 1
fi

# Verify replication is working with a baseline key
echo "Verifying baseline replication..."
redis-cli -p "$MASTER_PORT" SET baseline_key baseline_value &>/dev/null
for i in $(seq 1 20); do
    VAL=$(redis-cli -p "$REPLICA_PORT" GET baseline_key 2>/dev/null)
    if [ "$VAL" = "baseline_value" ]; then
        echo "Baseline replication confirmed."
        break
    fi
    sleep 0.5
done

# Step 1: Write a large value (16KB) to trigger a high read watermark on the replica
echo "Writing 16KB value to master to trigger high read watermark..."
LARGE_VALUE=$(python3 -c "print('a' * 16384)")
redis-cli -p "$MASTER_PORT" SET large_key "$LARGE_VALUE" &>/dev/null

# Wait for the large value to propagate
echo "Waiting for large value to propagate..."
for i in $(seq 1 20); do
    VAL=$(redis-cli -p "$REPLICA_PORT" GET large_key 2>/dev/null)
    if [ -n "$VAL" ] && [ ${#VAL} -gt 100 ]; then
        echo "Large value replicated."
        break
    fi
    sleep 0.5
done

# Step 2: Write a small value immediately after
echo "Writing small value to master..."
redis-cli -p "$MASTER_PORT" SET small_key small_value &>/dev/null

# Step 3: Check if the small value appears on the replica within 5 seconds
# With the bug, the replica's read watermark is stuck at 16KB, so the small
# replication data won't be processed until enough PINGs accumulate.
echo "Checking if small value replicates within 5 seconds..."
FOUND=false
for i in $(seq 1 50); do
    VAL=$(redis-cli -p "$REPLICA_PORT" GET small_key 2>/dev/null)
    if [ "$VAL" = "small_value" ]; then
        FOUND=true
        break
    fi
    sleep 0.1
done

if [ "$FOUND" = "true" ]; then
    echo ""
    echo "PASS: Bug is fixed — small value replicated promptly after large batch"
    exit 0
else
    echo ""
    echo "FAIL: Bug is present — small value not replicated within 5 seconds (replication stalled after large batch)"
    exit 1
fi
