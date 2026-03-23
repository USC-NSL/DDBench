#!/usr/bin/env bash
# Reproduction and verification script for clickhouse-99109-sum-nondeterministic
# Runs a ClickHouse process from source build, triggers the bug,
# and reports PASS/FAIL.
set -uo pipefail

CASE_NAME="clickhouse-99109-sum-nondeterministic"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/${CASE_NAME}"
CLICKHOUSE="$WORK_DIR/src/build/programs/clickhouse"

echo "=== Reproducing ${CASE_NAME} ==="

# ── Cleanup from previous runs ──
PID_SERVER=""
cleanup() {
    echo "Cleaning up..."
    [ -n "$PID_SERVER" ] && kill "$PID_SERVER" 2>/dev/null || true
    [ -n "$PID_SERVER" ] && wait "$PID_SERVER" 2>/dev/null || true
    rm -rf "$WORK_DIR/data"
}
trap cleanup EXIT

# Verify setup
if [ ! -x "$CLICKHOUSE" ]; then
    echo "ERROR: ClickHouse binary not found at $CLICKHOUSE. Run ./setup.sh first."
    exit 1
fi
if [ ! -f "$WORK_DIR/conf/server.xml" ]; then
    echo "ERROR: Config not found at $WORK_DIR/conf/server.xml. Run ./setup.sh first."
    exit 1
fi

# Prepare fresh data directory
rm -rf "$WORK_DIR/data"
mkdir -p "$WORK_DIR/data/tmp" "$WORK_DIR/data/user_files" "$WORK_DIR/data/format_schemas"
mkdir -p "$WORK_DIR/logs"

# ── Start ClickHouse ──
echo "Starting ClickHouse (tcp_port=9000, http_port=8123)..."
"$CLICKHOUSE" server \
    --config-file="$WORK_DIR/conf/server.xml" \
    &>"$WORK_DIR/logs/server.log" &
PID_SERVER=$!

# ── Wait for ClickHouse to be ready ──
echo "Waiting for ClickHouse to be ready..."
for i in $(seq 1 60); do
    if "$CLICKHOUSE" client -q "SELECT 1" &>/dev/null; then
        break
    fi
    if ! kill -0 "$PID_SERVER" 2>/dev/null; then
        echo "ERROR: ClickHouse process exited unexpectedly. Check $WORK_DIR/logs/server.log"
        exit 1
    fi
    sleep 1
done

# ── Create table and insert 200K+ rows with varied Float64 values ──
echo "Creating table and inserting 200K rows..."
"$CLICKHOUSE" client --multiquery -q "
CREATE TABLE float_sum_test (
    key UInt32,
    value Float64
) ENGINE = MergeTree()
ORDER BY key;

INSERT INTO float_sum_test
SELECT
    number % 10 AS key,
    (rand64() / 1e18) AS value
FROM numbers(200000);
"

# ── Compare sums with max_threads=1 vs max_threads=16 ──
echo "Comparing SUM results with max_threads=1 vs max_threads=16..."

# Run two separate queries and compare results
"$CLICKHOUSE" client -q "SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key ORDER BY key SETTINGS max_threads = 1" 2>/dev/null > "$WORK_DIR/sum_1thread.txt"
"$CLICKHOUSE" client -q "SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key ORDER BY key SETTINGS max_threads = 16" 2>/dev/null > "$WORK_DIR/sum_16thread.txt"

# Run multiple times to increase chance of nondeterminism
for run in $(seq 1 5); do
    "$CLICKHOUSE" client -q "SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key ORDER BY key SETTINGS max_threads = 16" 2>/dev/null > "$WORK_DIR/sum_16thread_run${run}.txt"
done

# Compare: count lines that differ
DIFF_COUNT=0
for run in $(seq 1 5); do
    d=$(diff "$WORK_DIR/sum_1thread.txt" "$WORK_DIR/sum_16thread_run${run}.txt" 2>/dev/null | grep "^[<>]" | wc -l)
    DIFF_COUNT=$((DIFF_COUNT + d))
done

# ── Evaluate ──
echo "Differing lines across 5 runs: $DIFF_COUNT"

if [ "$DIFF_COUNT" -eq 0 ] 2>/dev/null; then
    echo ""
    echo "PASS: Bug is fixed — all sums are identical regardless of thread count"
    exit 0
else
    echo ""
    echo "FAIL: Bug is present — $DIFF_COUNT keys have different sums between max_threads=1 and max_threads=16"
    exit 1
fi
