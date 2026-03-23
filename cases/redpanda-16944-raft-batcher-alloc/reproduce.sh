#!/usr/bin/env bash
# Reproduction and verification script for redpanda-16944-raft-batcher-alloc
# Runs Redpanda from source build, generates high write throughput,
# and checks for oversized allocation warnings from raft::replicate_batcher.
set -uo pipefail

CASE_NAME="redpanda-16944-raft-batcher-alloc"
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

# Prepare fresh data directory
rm -rf "$WORK_DIR/data"
mkdir -p "$WORK_DIR/data" "$WORK_DIR/logs"

# ── Start Redpanda with --smp 1 ──
# --smp 1: concentrate all raft batching on a single Seastar core
echo "Starting Redpanda (--smp 1, memory 2G)..."
"$REDPANDA" \
    --redpanda-cfg "$WORK_DIR/conf/redpanda.yaml" \
    --smp 1 \
    --memory 2G \
    &>"$WORK_DIR/logs/redpanda.log" &
PID_REDPANDA=$!

# ── Wait for Redpanda to be ready ──
echo "Waiting for Redpanda to start..."
for i in $(seq 1 30); do
    if "$RPK" cluster info --brokers 127.0.0.1:9092 &>/dev/null; then
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

# Set memory_allocation_warning_threshold via rpk after startup
# (this older version does not support it in the YAML config file)
echo "Setting memory_allocation_warning_threshold via rpk..."
"$RPK" cluster config set memory_allocation_warning_threshold 131073 --brokers 127.0.0.1:9092 &>/dev/null || true

# ── Create topics with many partitions to increase raft group load ──
echo "Creating topics..."
"$RPK" topic create batch-test-1 -p 50 --brokers 127.0.0.1:9092 2>/dev/null
"$RPK" topic create batch-test-2 -p 50 --brokers 127.0.0.1:9092 2>/dev/null
"$RPK" topic create batch-test-3 -p 50 --brokers 127.0.0.1:9092 2>/dev/null

# ── Generate high write throughput using rpk ──
echo "Generating high write throughput (this takes ~30 seconds)..."
for topic in batch-test-1 batch-test-2 batch-test-3; do
    (
        for i in $(seq 1 50000); do
            echo "payload-$i-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        done | "$RPK" topic produce "$topic" --brokers 127.0.0.1:9092 2>/dev/null
    ) &
done

# Wait for producers to finish
wait
echo "Write workload complete."

# Give a moment for any final log entries
sleep 3

# ── Check for oversized allocation warnings ──
echo "Checking logs for oversized allocation warnings..."
OVERSIZED=$(grep -c "oversized allocation" "$WORK_DIR/logs/redpanda.log" 2>/dev/null || echo "0")

echo ""
if [ "$OVERSIZED" -gt 0 ]; then
    echo "FAIL: Bug is present — found $OVERSIZED oversized allocation warning(s) from replicate_batcher"
    exit 1
else
    echo "PASS: Bug is fixed — no oversized allocation warnings found"
    exit 0
fi
