#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-3208-replication-watermark
# Master + replica: after a 16KB value is replicated, a following small write
# must reach the replica within 5 seconds (replication must not stall after a
# large batch).
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
MASTER_PORT=13208
REPLICA_PORT=13209
MASTER_DIR="$RUN_DIR/master"
REPLICA_DIR="$RUN_DIR/replica"
MASTER_CONF="$RUN_DIR/master.conf"
REPLICA_CONF="$RUN_DIR/replica.conf"

rebuild_worktree

# Verify setup
if [ ! -x "$BINARY" ]; then
    error "binary not found at $BINARY (run setup first)"
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

redis-cli -p "$MASTER_PORT" PING 2>/dev/null | grep -q PONG || fail "master did not start serving"

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

echo "$LINK_STATUS" | grep -q "up" || fail "replica did not complete the initial sync (${LINK_STATUS:-no answer})"

# Verify replication is working with a baseline key
echo "Verifying baseline replication..."
[ "$(redis-cli -p "$MASTER_PORT" SET baseline_key baseline_value 2>/dev/null)" = "OK" ] || fail "SET on the master failed"
BASELINE=false
for i in $(seq 1 20); do
    VAL=$(redis-cli -p "$REPLICA_PORT" GET baseline_key 2>/dev/null)
    if [ "$VAL" = "baseline_value" ]; then
        echo "Baseline replication confirmed."
        BASELINE=true
        break
    fi
    sleep 0.5
done

# Step 1: Write a large value (16KB) to trigger a high read watermark on the replica
echo "Writing 16KB value to master to trigger high read watermark..."
[ "$BASELINE" = true ] || fail "baseline replication did not work (replica never saw baseline_key)"
LARGE_VALUE=$(python3 -c "print('a' * 16384)")
[ "$(redis-cli -p "$MASTER_PORT" SET large_key "$LARGE_VALUE" 2>/dev/null)" = "OK" ] || error "SET of the 16KB value on the master failed (trigger not established)"

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
[ "$(redis-cli -p "$MASTER_PORT" SET small_key small_value 2>/dev/null)" = "OK" ] || fail "SET of the small value on the master failed"

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

[ "$FOUND" = "true" ] && pass "Bug is fixed — the small value replicated promptly after the large one"
fail "Bug is present — the small value did not reach the replica within 5 seconds (replication stalled after a large batch)"
