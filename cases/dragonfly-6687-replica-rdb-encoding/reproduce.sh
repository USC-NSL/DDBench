#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6687-replica-rdb-encoding
# Starts a master with tiered storage, loads data, starts a replica, and reports PASS/FAIL.
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6687-replica-rdb-encoding"
BINARY="$WORK_DIR/build-opt/dragonfly"
MASTER_PORT=16687
REPLICA_PORT=16688
DATA_DIR="/tmp/dragonfly-6687-data"
TIERED_PREFIX="/tmp/dragonfly-6687-tiered"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

# Cleanup from previous runs
pkill -f "dragonfly.*--port $MASTER_PORT" 2>/dev/null || true
pkill -f "dragonfly.*--port $REPLICA_PORT" 2>/dev/null || true
sleep 1
rm -rf "$DATA_DIR" "${TIERED_PREFIX}"* 2>/dev/null || true
mkdir -p "$DATA_DIR/master" "$DATA_DIR/replica"

echo "=== Reproducing dragonfly-6687-replica-rdb-encoding ==="

cleanup() {
    [ -n "${MASTER_PID:-}" ] && kill "$MASTER_PID" 2>/dev/null && wait "$MASTER_PID" 2>/dev/null
    [ -n "${REPLICA_PID:-}" ] && kill "$REPLICA_PID" 2>/dev/null && wait "$REPLICA_PID" 2>/dev/null
    rm -rf "$DATA_DIR" "${TIERED_PREFIX}"* 2>/dev/null || true
}
trap cleanup EXIT

# Start master with tiered storage
# Use 1 proactor thread (min tiered memory = 256MB).
# maxmemory=512mb with ~622MB of data forces aggressive tiered offloading.
echo "Starting master on port $MASTER_PORT with tiered storage..."
"$BINARY" --port "$MASTER_PORT" --logtostderr --proactor_threads 1 \
    --dbfilename="" --dir "$DATA_DIR/master" \
    --tiered_prefix="$TIERED_PREFIX" \
    --tiered_offload_threshold=1.0 \
    --serialization_max_chunk_size=64000 \
    --maxmemory=512mb &>/dev/null &
MASTER_PID=$!
sleep 3

# Check master started
if ! kill -0 "$MASTER_PID" 2>/dev/null; then
    echo "ERROR: Master failed to start."
    exit 1
fi

# Load data to trigger tiered storage offload
echo "Loading data (large strings + hashes)..."
redis-cli -p "$MASTER_PORT" DEBUG POPULATE 200000 key 3000 >/dev/null 2>&1
redis-cli -p "$MASTER_PORT" DEBUG POPULATE 200 hash 70 RAND TYPE HASH ELEMENTS 900 >/dev/null 2>&1
echo "Data loaded."

# Wait for tiered offloading to complete
echo "Waiting 15 seconds for tiered offloading..."
sleep 15

# Start replica
echo "Starting replica on port $REPLICA_PORT..."
"$BINARY" --port "$REPLICA_PORT" --logtostderr --proactor_threads 1 \
    --dbfilename="" --dir "$DATA_DIR/replica" \
    --maxmemory=1024mb &>"$DATA_DIR/replica.log" &
REPLICA_PID=$!
sleep 3

# Check replica started
if ! kill -0 "$REPLICA_PID" 2>/dev/null; then
    echo "ERROR: Replica failed to start."
    kill "$MASTER_PID" 2>/dev/null
    wait "$MASTER_PID" 2>/dev/null
    rm -rf "$DATA_DIR" "${TIERED_PREFIX}"* 2>/dev/null || true
    exit 1
fi

# Trigger replication
echo "Initiating replication: REPLICAOF localhost $MASTER_PORT"
redis-cli -p "$REPLICA_PORT" REPLICAOF localhost "$MASTER_PORT" >/dev/null 2>&1

# Wait for sync to complete (or fail)
echo "Waiting for sync (up to 45 seconds)..."
sleep 45

# Check replication status
LINK_STATUS=$(redis-cli -p "$REPLICA_PORT" INFO replication 2>/dev/null | grep master_link_status | tr -d '\r')

# Check replica logs for encoding error
ENCODING_ERROR=""
if [ -f "$DATA_DIR/replica.log" ]; then
    ENCODING_ERROR=$(grep -c "Unknown RDB string encoding" "$DATA_DIR/replica.log" 2>/dev/null || echo "0")
fi

# Cleanup
kill "$MASTER_PID" "$REPLICA_PID" 2>/dev/null
wait "$MASTER_PID" "$REPLICA_PID" 2>/dev/null
rm -rf "$DATA_DIR" "${TIERED_PREFIX}"* 2>/dev/null || true

# Report result
if echo "$LINK_STATUS" | grep -q "up"; then
    echo ""
    echo "PASS: Bug is fixed — replica synced successfully ($LINK_STATUS)"
    exit 0
else
    echo ""
    echo "FAIL: Bug is present — replica sync failed ($LINK_STATUS)"
    if [ "$ENCODING_ERROR" != "0" ] && [ -n "$ENCODING_ERROR" ]; then
        echo "  Replica logs contain $ENCODING_ERROR 'Unknown RDB string encoding' error(s)"
    fi
    exit 1
fi
