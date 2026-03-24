#!/usr/bin/env bash
# Reproduction and verification script for nats-7760-filter-stepdown
# Starts a 5-node cluster, creates stream/consumer, edits filter, steps down leader, and checks delivery.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/nats-7760-filter-stepdown"
BINARY="$WORK_DIR/nats-server"
DATA_DIR="$WORK_DIR/nats-7760-data"
NATS_CLI="$WORK_DIR/nats"

export PATH=$PATH:/usr/local/go/bin

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

# Use system nats CLI if local one not available
if [ ! -x "$NATS_CLI" ]; then
    if command -v nats &>/dev/null; then
        NATS_CLI="nats"
    else
        echo "ERROR: nats CLI not found. Run ./setup.sh first or install nats CLI."
        exit 1
    fi
fi

# Cleanup from previous runs
pkill -f "nats-server.*nats-7760" 2>/dev/null || true
sleep 1
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"

echo "=== Reproducing nats-7760-filter-stepdown ==="

cleanup() {
    pkill -f "nats-server.*nats-7760" 2>/dev/null || true
    sleep 1
    rm -rf "$DATA_DIR"
}
trap cleanup EXIT

# Create config files for 5-node cluster
for i in 1 2 3 4 5; do
cat > "$DATA_DIR/n${i}.conf" <<CONF
port: $((4320 + i))
server_name: n${i}
jetstream {
  store_dir: ${DATA_DIR}/n${i}
  max_mem: 64MB
  max_file: 256MB
}
cluster {
  name: test-cluster-7760
  listen: 0.0.0.0:$((6320 + i))
  routes: [
    nats-route://127.0.0.1:6321
    nats-route://127.0.0.1:6322
    nats-route://127.0.0.1:6323
    nats-route://127.0.0.1:6324
    nats-route://127.0.0.1:6325
  ]
}
CONF
done

# Start all 5 servers
echo "Starting 5-node NATS cluster..."
for i in 1 2 3 4 5; do
    "$BINARY" -c "$DATA_DIR/n${i}.conf" &>/dev/null &
done
sleep 5

export NATS_URL="nats://127.0.0.1:4321"

# Create an interest-based R5 stream
echo "Creating stream TEST..."
"$NATS_CLI" stream add TEST \
    --subjects="events.>" \
    --retention=interest \
    --replicas=5 \
    --storage=file \
    --defaults 2>/dev/null

# Create a consumer with filter subject
echo "Creating consumer myconsumer with filter events.a..."
"$NATS_CLI" consumer add TEST myconsumer \
    --filter="events.a" \
    --ack=explicit \
    --deliver=all \
    --replay=instant \
    --pull 2>/dev/null
sleep 1

# Edit consumer filter
echo "Editing consumer filter to events.b..."
"$NATS_CLI" consumer edit TEST myconsumer \
    --filter="events.b" 2>/dev/null
sleep 1

# Step down the stream leader
echo "Stepping down stream leader..."
"$NATS_CLI" stream cluster step-down TEST 2>/dev/null
sleep 3

# Publish messages matching the updated filter
echo "Publishing messages to events.b..."
"$NATS_CLI" pub events.b "test-message-7760" 2>/dev/null
sleep 1

# Try to consume
echo "Attempting to consume..."
OUTPUT=$("$NATS_CLI" consumer next TEST myconsumer --timeout=5s 2>&1 || true)

# Cleanup
pkill -f "nats-server.*nats-7760" 2>/dev/null || true
sleep 1
rm -rf "$DATA_DIR"

echo ""
if echo "$OUTPUT" | grep -q "test-message-7760"; then
    echo "PASS: Bug is fixed — consumer received message after filter edit and leader step-down"
    exit 0
else
    echo "FAIL: Bug is present — consumer did not receive message after filter edit and leader step-down"
    exit 1
fi
