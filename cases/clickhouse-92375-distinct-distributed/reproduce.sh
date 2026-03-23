#!/usr/bin/env bash
# Reproduction and verification script for clickhouse-92375-distinct-distributed
# Runs two ClickHouse shard processes from source build, triggers the bug,
# and reports PASS/FAIL.
set -uo pipefail

CASE_NAME="clickhouse-92375-distinct-distributed"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/${CASE_NAME}"
CLICKHOUSE="$WORK_DIR/src/build/programs/clickhouse"

echo "=== Reproducing ${CASE_NAME} ==="

# ── Cleanup from previous runs ──
PID_SHARD1=""
PID_SHARD2=""
cleanup() {
    echo "Cleaning up..."
    [ -n "$PID_SHARD1" ] && kill "$PID_SHARD1" 2>/dev/null || true
    [ -n "$PID_SHARD2" ] && kill "$PID_SHARD2" 2>/dev/null || true
    [ -n "$PID_SHARD1" ] && wait "$PID_SHARD1" 2>/dev/null || true
    [ -n "$PID_SHARD2" ] && wait "$PID_SHARD2" 2>/dev/null || true
    rm -rf "$WORK_DIR/data/shard1" "$WORK_DIR/data/shard2"
}
trap cleanup EXIT

# Verify setup
if [ ! -x "$CLICKHOUSE" ]; then
    echo "ERROR: ClickHouse binary not found at $CLICKHOUSE. Run ./setup.sh first."
    exit 1
fi
if [ ! -f "$WORK_DIR/conf/server-shard1.xml" ]; then
    echo "ERROR: Config not found at $WORK_DIR/conf/server-shard1.xml. Run ./setup.sh first."
    exit 1
fi

# Prepare fresh data directories
rm -rf "$WORK_DIR/data/shard1" "$WORK_DIR/data/shard2"
mkdir -p "$WORK_DIR/data/shard1/tmp" "$WORK_DIR/data/shard1/user_files" "$WORK_DIR/data/shard1/format_schemas"
mkdir -p "$WORK_DIR/data/shard2/tmp" "$WORK_DIR/data/shard2/user_files" "$WORK_DIR/data/shard2/format_schemas"
mkdir -p "$WORK_DIR/logs"

# ── Start shard 1 ──
echo "Starting shard 1 (tcp_port=9000, http_port=8123)..."
"$CLICKHOUSE" server \
    --config-file="$WORK_DIR/conf/server-shard1.xml" \
    &>"$WORK_DIR/logs/shard1.log" &
PID_SHARD1=$!

# ── Start shard 2 ──
echo "Starting shard 2 (tcp_port=9001, http_port=8124)..."
"$CLICKHOUSE" server \
    --config-file="$WORK_DIR/conf/server-shard2.xml" \
    &>"$WORK_DIR/logs/shard2.log" &
PID_SHARD2=$!

# ── Wait for both shards to be ready ──
echo "Waiting for shard 1 to be ready..."
for i in $(seq 1 60); do
    if "$CLICKHOUSE" client --port 9000 -q "SELECT 1" &>/dev/null; then
        break
    fi
    if ! kill -0 "$PID_SHARD1" 2>/dev/null; then
        echo "ERROR: Shard 1 process exited unexpectedly. Check $WORK_DIR/logs/shard1.log"
        exit 1
    fi
    sleep 1
done

echo "Waiting for shard 2 to be ready..."
for i in $(seq 1 60); do
    if "$CLICKHOUSE" client --port 9001 -q "SELECT 1" &>/dev/null; then
        break
    fi
    if ! kill -0 "$PID_SHARD2" 2>/dev/null; then
        echo "ERROR: Shard 2 process exited unexpectedly. Check $WORK_DIR/logs/shard2.log"
        exit 1
    fi
    sleep 1
done

# ── Create local tables on both shards (with enable_analyzer=1) ──
echo "Creating local tables on shard 1..."
"$CLICKHOUSE" client --port 9000 -q "
SET enable_analyzer = 1;
CREATE TABLE local_table ENGINE = Memory() AS SELECT * FROM numbers(2);
" 2>/dev/null

echo "Creating local tables on shard 2..."
"$CLICKHOUSE" client --port 9001 -q "
SET enable_analyzer = 1;
CREATE TABLE local_table ENGINE = Memory() AS SELECT * FROM numbers(2);
" 2>/dev/null

# ── Create distributed table on shard 1 ──
echo "Creating distributed table..."
"$CLICKHOUSE" client --port 9000 -q "
CREATE TABLE distributed_table AS local_table
ENGINE = Distributed('test_cluster_two_shards', currentDatabase(), 'local_table', rand());
" 2>/dev/null

# ── Query with optimize_skip_unused_shards = 0 ──
echo "Running query with optimize_skip_unused_shards=0..."
R0=$("$CLICKHOUSE" client --port 9000 -q "
SET enable_analyzer = 1;
SET optimize_skip_unused_shards = 0;
SELECT count() FROM (SELECT DISTINCT number FROM distributed_table);
" 2>/dev/null)

# ── Query with optimize_skip_unused_shards = 1 ──
echo "Running query with optimize_skip_unused_shards=1..."
R1=$("$CLICKHOUSE" client --port 9000 -q "
SET enable_analyzer = 1;
SET optimize_skip_unused_shards = 1;
SELECT count() FROM (SELECT DISTINCT number FROM distributed_table);
" 2>/dev/null)

# ── Evaluate ──
echo "Result with optimize_skip_unused_shards=0: $R0"
echo "Result with optimize_skip_unused_shards=1: $R1"

if [ "$R0" = "$R1" ] && [ "$R0" = "2" ]; then
    echo ""
    echo "PASS: Bug is fixed — both queries return 2"
    exit 0
else
    echo ""
    echo "FAIL: Bug is present — optimize_skip_unused_shards=0 returned $R0, optimize_skip_unused_shards=1 returned $R1 (expected both to return 2)"
    exit 1
fi
