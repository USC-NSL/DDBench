#!/usr/bin/env bash
# Reproduction and verification script for redpanda-25769-listoffsets-wrong
# Runs Redpanda from source build or extracted binary, produces compressed
# records with known timestamps, queries ListOffsets by timestamp, and checks correctness.
set -uo pipefail

CASE_NAME="redpanda-25769-listoffsets-wrong"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/${CASE_NAME}"
REDPANDA="$WORK_DIR/bin/redpanda"
RPK="$WORK_DIR/bin/rpk"

echo "=== Reproducing ${CASE_NAME} ==="

# ── Cleanup from previous runs ──
PID_REDPANDA=""
cleanup() {
    echo "Cleaning up..."
    [ -n "$PID_REDPANDA" ] && kill "$PID_REDPANDA" 2>/dev/null || true
    [ -n "$PID_REDPANDA" ] && wait "$PID_REDPANDA" 2>/dev/null || true
    rm -rf "$WORK_DIR/data"
}
trap cleanup EXIT

# Verify setup
if [ ! -x "$REDPANDA" ]; then
    echo "ERROR: Redpanda binary not found at $REDPANDA. Run ./setup.sh first."
    exit 1
fi
if [ ! -x "$RPK" ]; then
    echo "ERROR: rpk binary not found at $RPK. Run ./setup.sh first."
    exit 1
fi
if [ ! -f "$WORK_DIR/conf/redpanda.yaml" ]; then
    echo "ERROR: Config not found at $WORK_DIR/conf/redpanda.yaml. Run ./setup.sh first."
    exit 1
fi

# Ensure confluent-kafka Python library is installed
PYTHON_CMD="python3"
command -v python3 &>/dev/null || PYTHON_CMD="python"
echo "Ensuring confluent-kafka Python library is installed..."
$PYTHON_CMD -c "import confluent_kafka" 2>/dev/null || {
    pip3 install confluent-kafka 2>/dev/null || pip install confluent-kafka 2>/dev/null || {
        echo "ERROR: Failed to install confluent-kafka. Please install Python 3 and pip."
        exit 1
    }
}

# Prepare fresh data directory
rm -rf "$WORK_DIR/data"
mkdir -p "$WORK_DIR/data" "$WORK_DIR/logs"

# ── Start Redpanda ──
echo "Starting Redpanda..."
"$REDPANDA" \
    --redpanda-cfg "$WORK_DIR/conf/redpanda.yaml" \
    --smp 1 \
    --memory 1G \
    &>"$WORK_DIR/logs/redpanda.log" &
PID_REDPANDA=$!

# ── Wait for Redpanda to be ready ──
echo "Waiting for Redpanda to start..."
for i in $(seq 1 30); do
    if "$RPK" cluster info --brokers localhost:9092 &>/dev/null; then
        echo "Redpanda is ready."
        break
    fi
    if ! kill -0 "$PID_REDPANDA" 2>/dev/null; then
        echo "ERROR: Redpanda process exited unexpectedly. Check $WORK_DIR/logs/redpanda.log"
        exit 1
    fi
    if [ "$i" -eq 30 ]; then
        echo "ERROR: Redpanda failed to start within 30 seconds."
        exit 1
    fi
    sleep 1
done

# ── Create topic ──
echo "Creating topic..."
"$RPK" topic create test-compressed -p 1 --brokers localhost:9092

# ── Write and run the Python test script ──
cat > "$WORK_DIR/test_listoffsets.py" << 'PYEOF'
import sys
import time
from confluent_kafka import Producer, Consumer, TopicPartition

BROKER = "localhost:9092"
TOPIC = "test-compressed"

# Timestamps in milliseconds -- spaced 1 hour apart
TIMESTAMPS_MS = [
    1704067200000,  # 2024-01-01 00:00:00 UTC -> expected offset 0
    1704070800000,  # 2024-01-01 01:00:00 UTC -> expected offset 1
    1704074400000,  # 2024-01-01 02:00:00 UTC -> expected offset 2
    1704078000000,  # 2024-01-01 03:00:00 UTC -> expected offset 3
    1704081600000,  # 2024-01-01 04:00:00 UTC -> expected offset 4
]

def delivery_callback(err, msg):
    if err:
        print(f"ERROR: Delivery failed: {err}")
        sys.exit(1)

# Produce 5 records with distinct timestamps in a single compressed batch
producer = Producer({
    "bootstrap.servers": BROKER,
    "compression.type": "gzip",
    "batch.size": 1048576,       # 1 MB -- large enough to hold all 5 records
    "linger.ms": 5000,           # wait 5 seconds to accumulate records into one batch
})

print("Producing 5 compressed records with distinct timestamps...")
for i, ts_ms in enumerate(TIMESTAMPS_MS):
    producer.produce(
        topic=TOPIC,
        value=f"record-{i}".encode(),
        timestamp=ts_ms,
        callback=delivery_callback,
    )

# Flush sends all buffered records as a single compressed batch
producer.flush(timeout=30)
print("All records produced and flushed as a single compressed batch.")

# Brief pause to let Redpanda finalize
time.sleep(2)

# Query ListOffsets for the timestamp of record 2 (offset 2)
# Expected: offset 2
# Bug: returns offset 0 (start of compressed batch)
query_ts = TIMESTAMPS_MS[2]  # 2024-01-01 02:00:00 UTC
expected_offset = 2

consumer = Consumer({
    "bootstrap.servers": BROKER,
    "group.id": "test-listoffsets-group",
    "auto.offset.reset": "earliest",
})

print(f"Querying ListOffsets for timestamp {query_ts} (expected offset: {expected_offset})...")
tp = TopicPartition(TOPIC, 0, query_ts)
result = consumer.offsets_for_times([tp], timeout=10)

if not result:
    print("ERROR: offsets_for_times returned no results")
    consumer.close()
    sys.exit(1)

returned_offset = result[0].offset
print(f"ListOffsets returned offset: {returned_offset}")

consumer.close()

if returned_offset == expected_offset:
    print("RESULT:PASS")
else:
    print(f"RESULT:FAIL (returned {returned_offset}, expected {expected_offset})")
PYEOF

echo "Running ListOffsets test..."
TEST_OUTPUT=$($PYTHON_CMD "$WORK_DIR/test_listoffsets.py" 2>&1)
echo "$TEST_OUTPUT"

# Extract result
RESULT=$(echo "$TEST_OUTPUT" | grep "^RESULT:" | tail -1)

echo ""
if echo "$RESULT" | grep -q "RESULT:PASS"; then
    echo "PASS: Bug is fixed — ListOffsets returns correct offset for compressed batch"
    exit 0
else
    echo "FAIL: Bug is present — ListOffsets returned wrong offset for compressed batch"
    exit 1
fi
