#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-2214-slave-sync-gap
# Starts a Kvrocks cluster (master + replica) with repl-namespace-enabled,
# writes keys, restarts the replica, and checks if keys written during
# downtime are correctly replicated. Reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-2214-slave-sync-gap"
BINARY="$WORK_DIR/build/kvrocks"
MASTER_PORT=12214
SLAVE_PORT=12215
MASTER_DIR="$WORK_DIR/kvrocks-2214-master"
SLAVE_DIR="$WORK_DIR/kvrocks-2214-slave"
MASTER_CONF="$WORK_DIR/kvrocks-2214-master.conf"
SLAVE_CONF="$WORK_DIR/kvrocks-2214-slave.conf"

MASTER_NODE_ID="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx00"
SLAVE_NODE_ID="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx01"

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
    kill "$SLAVE_PID" 2>/dev/null || true
    wait "$MASTER_PID" 2>/dev/null || true
    wait "$SLAVE_PID" 2>/dev/null || true
    rm -rf "$MASTER_DIR" "$SLAVE_DIR"
    rm -f "$MASTER_CONF" "$SLAVE_CONF"
}
trap cleanup EXIT

# Cleanup from previous runs
pkill -f "kvrocks.*-c $MASTER_CONF" 2>/dev/null || true
pkill -f "kvrocks.*-c $SLAVE_CONF" 2>/dev/null || true
sleep 1
rm -rf "$MASTER_DIR" "$SLAVE_DIR"
mkdir -p "$MASTER_DIR/logs" "$SLAVE_DIR/logs"

MASTER_PID=""
SLAVE_PID=""

echo "=== Reproducing kvrocks-2214-slave-sync-gap ==="

# ── Helper: wait for Kvrocks to accept connections ──
wait_for_port() {
    local port=$1 label=$2 timeout=30
    echo "Waiting for $label on port $port..."
    for i in $(seq 1 $timeout); do
        if redis-cli -p "$port" PING 2>/dev/null | grep -qi pong; then
            echo "$label is ready."
            return 0
        fi
        sleep 1
    done
    echo "ERROR: $label did not become ready within ${timeout}s."
    return 1
}

# ── Helper: wait for slave replication to be up ──
wait_for_replication() {
    local timeout=60
    echo "Waiting for slave replication to be up..."
    for i in $(seq 1 $timeout); do
        local info
        info=$(redis-cli -p "$SLAVE_PORT" INFO replication 2>/dev/null)
        if echo "$info" | grep -q "master_link_status:up"; then
            echo "Slave replication is up."
            return 0
        fi
        sleep 1
    done
    echo "ERROR: Slave replication did not come up within ${timeout}s."
    return 1
}

# ── Helper: wait for offset sync between master and replica ──
wait_for_offset_sync() {
    local timeout=30
    echo "Waiting for replication offset sync..."
    for i in $(seq 1 $timeout); do
        local master_offset slave_offset
        master_offset=$(redis-cli -p "$MASTER_PORT" INFO replication 2>/dev/null | grep "master_repl_offset:" | tr -d '\r' | cut -d: -f2)
        slave_offset=$(redis-cli -p "$SLAVE_PORT" INFO replication 2>/dev/null | grep "master_repl_offset:" | tr -d '\r' | cut -d: -f2)
        if [ -n "$master_offset" ] && [ -n "$slave_offset" ] && [ "$master_offset" = "$slave_offset" ]; then
            echo "Offsets synced at $master_offset."
            return 0
        fi
        sleep 1
    done
    echo "WARNING: Offset sync timeout after ${timeout}s."
    return 0
}

# ── Create master config (CLUSTER MODE) ──
cat > "$MASTER_CONF" <<EOF
bind 0.0.0.0
port $MASTER_PORT
dir $MASTER_DIR
log-dir $MASTER_DIR/logs
cluster-enabled yes
EOF

# ── Create slave config (CLUSTER MODE + repl-namespace-enabled) ──
cat > "$SLAVE_CONF" <<EOF
bind 0.0.0.0
port $SLAVE_PORT
dir $SLAVE_DIR
log-dir $SLAVE_DIR/logs
cluster-enabled yes
repl-namespace-enabled yes
EOF

# ── Step 1: Start master ──
echo ""
echo "Step 1: Starting master on port $MASTER_PORT (cluster mode)..."
"$BINARY" -c "$MASTER_CONF" &>/dev/null &
MASTER_PID=$!

if ! wait_for_port "$MASTER_PORT" "Master"; then
    exit 1
fi

# Set master node ID
redis-cli -p "$MASTER_PORT" clusterx SETNODEID "$MASTER_NODE_ID" 2>/dev/null

# ── Step 2: Start slave ──
echo ""
echo "Step 2: Starting slave on port $SLAVE_PORT (cluster mode + repl-namespace-enabled)..."
"$BINARY" -c "$SLAVE_CONF" &>/dev/null &
SLAVE_PID=$!

if ! wait_for_port "$SLAVE_PORT" "Slave"; then
    exit 1
fi

# Set slave node ID
redis-cli -p "$SLAVE_PORT" clusterx SETNODEID "$SLAVE_NODE_ID" 2>/dev/null

# ── Step 3: Set up cluster topology ──
echo ""
echo "Step 3: Setting up cluster topology..."
CLUSTER_NODES="${MASTER_NODE_ID} 127.0.0.1 ${MASTER_PORT} master - 0-16383
${SLAVE_NODE_ID} 127.0.0.1 ${SLAVE_PORT} slave ${MASTER_NODE_ID}"

redis-cli -p "$MASTER_PORT" clusterx SETNODES "$CLUSTER_NODES" "1" 2>/dev/null
redis-cli -p "$SLAVE_PORT" clusterx SETNODES "$CLUSTER_NODES" "1" 2>/dev/null

if ! wait_for_replication; then
    exit 1
fi

# ── Helper: read from slave in cluster mode (READONLY must be in same connection) ──
slave_get() {
    local key=$1
    printf "READONLY\r\nGET %s\r\n" "$key" | redis-cli -p "$SLAVE_PORT" 2>/dev/null | tail -1
}

slave_hget() {
    local key=$1 field=$2
    printf "READONLY\r\nHGET %s %s\r\n" "$key" "$field" | redis-cli -p "$SLAVE_PORT" 2>/dev/null | tail -1
}

# ── Step 4: Write initial keys and verify replication ──
echo ""
echo "Step 4: Setting k0=v0 on master..."
redis-cli -p "$MASTER_PORT" SET k0 v0 2>/dev/null
redis-cli -p "$MASTER_PORT" LPUSH k1 e0 e1 e2 2>/dev/null

wait_for_offset_sync

SLAVE_K0=$(slave_get k0)
echo "Slave GET k0 = '$SLAVE_K0'"
if [ "$SLAVE_K0" != "v0" ]; then
    echo "ERROR: Initial replication failed (got '$SLAVE_K0')."
    exit 1
fi
echo "Initial replication verified."

# ── Step 5: Stop slave ──
echo ""
echo "Step 5: Stopping slave..."
kill "$SLAVE_PID" 2>/dev/null
wait "$SLAVE_PID" 2>/dev/null || true
SLAVE_PID=""
sleep 1

# ── Step 6: Write updates on master while slave is down ──
echo ""
echo "Step 6: Updating keys on master while slave is down..."
redis-cli -p "$MASTER_PORT" SET k0 v1 2>/dev/null
redis-cli -p "$MASTER_PORT" HSET k2 f0 v0 f1 v1 2>/dev/null
echo "Master SET k0=v1, HSET k2 f0=v0 f1=v1"

# ── Step 7: Restart slave ──
echo ""
echo "Step 7: Restarting slave..."
"$BINARY" -c "$SLAVE_CONF" &>/dev/null &
SLAVE_PID=$!

if ! wait_for_port "$SLAVE_PORT" "Slave"; then
    exit 1
fi

if ! wait_for_replication; then
    exit 1
fi

wait_for_offset_sync
# Extra time for data to propagate
sleep 3

# ── Step 8: Verify replication ──
echo ""
echo "Step 8: Checking slave for replicated keys..."
SLAVE_K0=$(slave_get k0)
SLAVE_K2_F0=$(slave_hget k2 f0)
SLAVE_K2_F1=$(slave_hget k2 f1)
echo "Slave GET k0 = '$SLAVE_K0' (expected 'v1')"
echo "Slave HGET k2 f0 = '$SLAVE_K2_F0' (expected 'v0')"
echo "Slave HGET k2 f1 = '$SLAVE_K2_F1' (expected 'v1')"

# ── Verdict ──
BUGS_FOUND=0
if [ "$SLAVE_K0" != "v1" ]; then
    echo "DETAIL: k0 is stale on slave ('$SLAVE_K0' instead of 'v1')."
    BUGS_FOUND=1
fi
if [ "$SLAVE_K2_F0" != "v0" ] || [ "$SLAVE_K2_F1" != "v1" ]; then
    echo "DETAIL: k2 hash is missing or wrong on slave."
    BUGS_FOUND=1
fi

echo ""
if [ "$BUGS_FOUND" -eq 1 ]; then
    echo "FAIL: Bug is present — slave lost key updates that occurred during its downtime"
    exit 1
else
    echo "PASS: Bug is fixed — slave correctly received all key updates after restart"
    exit 0
fi
