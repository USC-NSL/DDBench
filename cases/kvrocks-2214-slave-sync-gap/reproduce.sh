#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-2214-slave-sync-gap
# Cluster mode with repl-namespace-enabled on the replica: replicate k0, stop
# the replica, update k0 and add a hash k2 on the master, restart the replica,
# and check that the replica has the updates made while it was down.
#
# Exit codes: 0 = PASS (bug fixed), 1 = FAIL (bug present, or the worktree does
# not build / the code under test does not start), 2 = ERROR (oracle or
# infrastructure problem; the verdict is inconclusive).
# ── Runs only inside the bench.sh reproduce container (BENCH_WORKDIR is set) ──
if [ -z "${BENCH_WORKDIR:-}" ]; then
    CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    [ -f "$REPO_ROOT/bench.sh" ] && exec bash "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
    echo "ERROR: run this oracle with ./bench.sh reproduce $CASE_NAME" >&2
    exit 2
fi
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$BENCH_WORKDIR"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ddbench.XXXXXX")"   # scratch space outside the worktree

pass()  { echo ""; echo "PASS: $*"; exit 0; }
fail()  { echo ""; echo "FAIL: $*"; exit 1; }
error() { echo ""; echo "ERROR: $*"; exit 2; }

# REBUILD.sh is the worktree's designated build entry point.
rebuild_worktree() {
    [ -f "$WORK_DIR/REBUILD.sh" ] || error "REBUILD.sh not found in $WORK_DIR (run setup first)"
    bash "$WORK_DIR/REBUILD.sh" || fail "the worktree does not build (REBUILD.sh exited non-zero)"
}


BINARY="$WORK_DIR/build/kvrocks"
MASTER_PORT=12214
SLAVE_PORT=12215
MASTER_DIR="$RUN_DIR/master"
SLAVE_DIR="$RUN_DIR/slave"
MASTER_CONF="$RUN_DIR/master.conf"
SLAVE_CONF="$RUN_DIR/slave.conf"

MASTER_NODE_ID="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx00"
SLAVE_NODE_ID="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx01"

rebuild_worktree

# Verify setup
if [ ! -x "$BINARY" ]; then
    error "binary not found at $BINARY (run setup first)"
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
    fail "master did not start serving"
fi

# Set master node ID
redis-cli -p "$MASTER_PORT" clusterx SETNODEID "$MASTER_NODE_ID" 2>/dev/null

# ── Step 2: Start slave ──
echo ""
echo "Step 2: Starting slave on port $SLAVE_PORT (cluster mode + repl-namespace-enabled)..."
"$BINARY" -c "$SLAVE_CONF" &>/dev/null &
SLAVE_PID=$!

if ! wait_for_port "$SLAVE_PORT" "Slave"; then
    fail "replica did not start serving"
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
    fail "replication link did not come up"
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
    fail "initial replication failed (replica GET k0 = '$SLAVE_K0')"
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
    fail "replica did not start serving"
fi

if ! wait_for_replication; then
    fail "replication link did not come up"
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

[ "$BUGS_FOUND" -eq 1 ] && fail "Bug is present — the replica lost key updates made while it was down"
pass "Bug is fixed — the replica received all key updates made while it was down"
