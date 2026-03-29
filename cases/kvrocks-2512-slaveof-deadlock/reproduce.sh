#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-2512-slaveof-deadlock
# Instruments the source with a sleep in PrepareRestoreDB to widen the
# deadlock race window. Forces full sync by enabling use-rsid-psync.
# If the slave deadlocks (PING times out) -> FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-2512-slaveof-deadlock"
BINARY="$WORK_DIR/build/kvrocks"
MASTER1_PORT=12512
MASTER2_PORT=12513
SLAVE_PORT=12514
MASTER1_DIR="$WORK_DIR/kvrocks-2512-master1"
MASTER2_DIR="$WORK_DIR/kvrocks-2512-master2"
SLAVE_DIR="$WORK_DIR/kvrocks-2512-slave"
MASTER1_CONF="$WORK_DIR/kvrocks-2512-master1.conf"
MASTER2_CONF="$WORK_DIR/kvrocks-2512-master2.conf"
SLAVE_CONF="$WORK_DIR/kvrocks-2512-slave.conf"
SOURCE_FILE="$WORK_DIR/src/server/server.cc"

# ── Instrument source to widen the deadlock race window ──
INSTRUMENT_MARKER="BUG_BENCH_DEADLOCK_INSTRUMENT"
needs_rebuild=false
if ! grep -q "$INSTRUMENT_MARKER" "$SOURCE_FILE" 2>/dev/null; then
    echo "Instrumenting source to widen deadlock race window..."
    needs_rebuild=true

    if ! grep -q '#include <thread>' "$SOURCE_FILE"; then
        sed -i '1 i\#include <thread>  // '"$INSTRUMENT_MARKER" "$SOURCE_FILE"
    fi

    # Add 2-second sleep before WorkExclusivityGuard in PrepareRestoreDB
    sed -i '/Waiting workers for finishing executing commands/a\    /* '"$INSTRUMENT_MARKER"' */ LOG(INFO) << "[server] INSTRUMENT: sleeping 2s before exclusive guard"; std::this_thread::sleep_for(std::chrono::seconds(2));' "$SOURCE_FILE"

    if grep -q "$INSTRUMENT_MARKER" "$SOURCE_FILE"; then
        echo "Instrumentation applied."
    else
        echo "ERROR: Instrumentation failed."
        exit 1
    fi
fi

if [ "$needs_rebuild" = "true" ]; then
    echo "Rebuilding with instrumentation (incremental)..."
    cd "$WORK_DIR/build"
    make -j$(nproc) kvrocks 2>&1 | tail -5
    cd "$WORK_DIR"
    echo "Instrumented build complete."
fi

if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

MASTER1_PID=""
MASTER2_PID=""
SLAVE_PID=""

cleanup() {
    echo "Cleaning up..."
    pkill -9 -f "redis-cli.*-p $SLAVE_PORT" 2>/dev/null || true
    # Use SIGKILL — a deadlocked kvrocks ignores SIGTERM
    kill -9 "$MASTER1_PID" 2>/dev/null || true
    kill -9 "$MASTER2_PID" 2>/dev/null || true
    kill -9 "$SLAVE_PID" 2>/dev/null || true
    wait "$MASTER1_PID" 2>/dev/null || true
    wait "$MASTER2_PID" 2>/dev/null || true
    wait "$SLAVE_PID" 2>/dev/null || true
    rm -rf "$MASTER1_DIR" "$MASTER2_DIR" "$SLAVE_DIR"
    rm -f "$MASTER1_CONF" "$MASTER2_CONF" "$SLAVE_CONF"

    if grep -q "$INSTRUMENT_MARKER" "$SOURCE_FILE" 2>/dev/null; then
        echo "Removing instrumentation from source..."
        sed -i "/$INSTRUMENT_MARKER/d" "$SOURCE_FILE"
    fi
}
trap cleanup EXIT

pkill -9 -f "kvrocks.*-c $MASTER1_CONF" 2>/dev/null || true
pkill -9 -f "kvrocks.*-c $MASTER2_CONF" 2>/dev/null || true
pkill -9 -f "kvrocks.*-c $SLAVE_CONF" 2>/dev/null || true
sleep 1
rm -rf "$MASTER1_DIR" "$MASTER2_DIR" "$SLAVE_DIR"
mkdir -p "$MASTER1_DIR" "$MASTER2_DIR" "$SLAVE_DIR"

echo "=== Reproducing kvrocks-2512-slaveof-deadlock ==="

wait_for_port() {
    local port=$1 label=$2 timeout_s=30
    echo "Waiting for $label on port $port..."
    for i in $(seq 1 $timeout_s); do
        if timeout 2 redis-cli -p "$port" PING 2>/dev/null | grep -qi pong; then
            echo "$label is ready."
            return 0
        fi
        sleep 1
    done
    echo "ERROR: $label did not become ready within ${timeout_s}s."
    return 1
}

# ── Configs with use-rsid-psync to force full sync on master switch ──
cat > "$MASTER1_CONF" <<EOF
bind 0.0.0.0
port $MASTER1_PORT
dir $MASTER1_DIR
log-dir $MASTER1_DIR
use-rsid-psync yes
EOF

cat > "$MASTER2_CONF" <<EOF
bind 0.0.0.0
port $MASTER2_PORT
dir $MASTER2_DIR
log-dir $MASTER2_DIR
use-rsid-psync yes
EOF

cat > "$SLAVE_CONF" <<EOF
bind 0.0.0.0
port $SLAVE_PORT
dir $SLAVE_DIR
log-dir $SLAVE_DIR
use-rsid-psync yes
slave-empty-db-before-fullsync yes
EOF

echo ""
echo "Step 1: Starting master1 on port $MASTER1_PORT..."
"$BINARY" -c "$MASTER1_CONF" &>/dev/null &
MASTER1_PID=$!
if ! wait_for_port "$MASTER1_PORT" "Master1"; then exit 1; fi

echo ""
echo "Step 2: Starting master2 on port $MASTER2_PORT..."
"$BINARY" -c "$MASTER2_CONF" &>/dev/null &
MASTER2_PID=$!
if ! wait_for_port "$MASTER2_PORT" "Master2"; then exit 1; fi

echo ""
echo "Step 3: Starting slave on port $SLAVE_PORT..."
"$BINARY" -c "$SLAVE_CONF" &>/dev/null &
SLAVE_PID=$!
if ! wait_for_port "$SLAVE_PORT" "Slave"; then exit 1; fi

echo ""
echo "Step 4: Verifying all instances respond to PING..."
for port in $MASTER1_PORT $MASTER2_PORT $SLAVE_PORT; do
    PONG=$(timeout 3 redis-cli -p "$port" PING 2>/dev/null)
    if [ "$PONG" != "PONG" ]; then
        echo "ERROR: Instance on port $port not responding."
        exit 1
    fi
done
echo "All instances responsive."

# ── Step 5: Write data and establish replication with master2 ──
echo ""
echo "Step 5: Writing data and establishing replication with master2..."
redis-cli -p "$MASTER1_PORT" SET "m1key" "m1val" &>/dev/null
redis-cli -p "$MASTER2_PORT" SET "m2key" "m2val" &>/dev/null
timeout 3 redis-cli -p "$SLAVE_PORT" SLAVEOF 127.0.0.1 "$MASTER2_PORT" &>/dev/null

echo "Waiting for slave to sync with master2..."
for i in $(seq 1 30); do
    LINK=$(timeout 2 redis-cli -p "$SLAVE_PORT" INFO replication 2>/dev/null | grep "master_link_status" | tr -d '\r')
    if echo "$LINK" | grep -q "up"; then
        echo "Slave synced with master2."
        break
    fi
    sleep 1
done
# Wait for full sync to complete fully (including the 2s instrumented sleep)
sleep 5

# ── Step 6: Trigger the deadlock ──
# Now switch to master1. Since the slave has master2's replication ID and
# use-rsid-psync is enabled, PSYNC with master1 will fail -> full sync.
# The repl thread enters PrepareRestoreDB ~100ms after SLAVEOF and hits
# the 2s instrumented sleep. We send the second SLAVEOF 500ms after the
# first, during the sleep window. The second SLAVEOF acquires the exclusive
# lock and calls Stop/join -> the old repl thread is waiting for the same
# exclusive lock -> DEADLOCK.
echo ""
echo "Step 6: Triggering deadlock with SLAVEOF master switching..."
DEADLOCKED=false

for attempt in $(seq 1 3); do
    echo "  Attempt $attempt:"
    echo "    SLAVEOF to master1 (forces full sync -> PrepareRestoreDB with 2s sleep)..."
    timeout 3 redis-cli -p "$SLAVE_PORT" SLAVEOF 127.0.0.1 "$MASTER1_PORT" &>/dev/null

    # Wait ~500ms for repl thread to connect, fail PSYNC, and enter
    # PrepareRestoreDB where it hits the 2s instrumented sleep.
    # The repl thread reaches the sleep in ~100-200ms.
    sleep 0.5

    echo "    SLAVEOF to master2 (should acquire exclusive lock and deadlock)..."
    # This SLAVEOF acquires the exclusive lock and calls Stop/join on the old
    # repl thread. The old repl thread is sleeping before WorkExclusivityGuard.
    # When it wakes up and tries to acquire the exclusive lock -> DEADLOCK.
    # The redis-cli will hang because the worker thread is stuck on join.
    timeout 10 redis-cli -p "$SLAVE_PORT" SLAVEOF 127.0.0.1 "$MASTER2_PORT" &>/dev/null
    SLAVEOF_RC=$?

    if [ "$SLAVEOF_RC" -eq 124 ]; then
        echo "    Second SLAVEOF timed out (server deadlocked)!"
        DEADLOCKED=true
        break
    fi

    # Check slave health — distinguish deadlock (no response) from loading (alive but busy).
    # On the fixed code, is_loading_ is set early, so PING gets "LOADING" error (not a deadlock).
    # On the buggy code, the server is truly deadlocked and times out.
    sleep 1
    RESP=$(timeout 5 redis-cli -p "$SLAVE_PORT" PING 2>&1)
    if echo "$RESP" | grep -qi "pong"; then
        echo "    Slave still responsive."
    elif echo "$RESP" | grep -qi "loading"; then
        echo "    Slave alive but loading (is_loading_ set early — fix is working)."
        # Wait for loading to clear before next attempt
        sleep 8
    else
        echo "    Slave stopped responding (deadlocked)!"
        DEADLOCKED=true
        break
    fi
    echo "    Waiting for full sync to complete..."
    sleep 5
done

echo ""
echo "Step 7: Final PING check on slave (15s, retries through loading state)..."
FINAL_PONG=""
for i in $(seq 1 15); do
    RESP=$(timeout 5 redis-cli -p "$SLAVE_PORT" PING 2>&1)
    if echo "$RESP" | grep -qi "pong"; then
        FINAL_PONG="PONG"
        break
    elif echo "$RESP" | grep -qi "loading"; then
        echo "  Still loading... ($i/15)"
        sleep 1
    else
        sleep 1
    fi
done

if [ "$DEADLOCKED" = "true" ] || [ "$FINAL_PONG" != "PONG" ]; then
    echo ""
    echo "FAIL: Bug is present — slave deadlocked after rapid SLAVEOF master switching"
    exit 1
else
    echo ""
    echo "PASS: Bug is fixed — slave remains responsive after rapid SLAVEOF master switching"
    exit 0
fi
