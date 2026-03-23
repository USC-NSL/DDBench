#!/usr/bin/env bash
# Reproduction and verification script for clickhouse-29332-predicate-pushdown
# Runs two ClickHouse shard processes from source build, triggers the bug,
# and reports PASS/FAIL.
set -uo pipefail

CASE_NAME="clickhouse-29332-predicate-pushdown"
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

# ── Create local tables on both shards ──
echo "Creating local tables on shard 1..."
"$CLICKHOUSE" client --port 9000 --multiquery -q "
CREATE TABLE IF NOT EXISTS local_t1 (id UInt64, value String) ENGINE = MergeTree() ORDER BY id;
CREATE TABLE IF NOT EXISTS local_t2 (id UInt64, name String) ENGINE = MergeTree() ORDER BY id;
"

echo "Creating local tables on shard 2..."
"$CLICKHOUSE" client --port 9001 --multiquery -q "
CREATE TABLE IF NOT EXISTS local_t1 (id UInt64, value String) ENGINE = MergeTree() ORDER BY id;
CREATE TABLE IF NOT EXISTS local_t2 (id UInt64, name String) ENGINE = MergeTree() ORDER BY id;
"

# ── Create distributed tables and insert data on shard 1 ──
echo "Creating distributed tables and inserting data..."
"$CLICKHOUSE" client --port 9000 --multiquery -q "
CREATE TABLE IF NOT EXISTS dist_t1 AS local_t1 ENGINE = Distributed('test_cluster', currentDatabase(), 'local_t1', id);
CREATE TABLE IF NOT EXISTS dist_t2 AS local_t2 ENGINE = Distributed('test_cluster', currentDatabase(), 'local_t2', id);
INSERT INTO local_t1 VALUES (1, 'a'), (2, 'b'), (3, 'c');
INSERT INTO local_t2 VALUES (1, 'alpha'), (2, 'beta');
"

# ── Run the test query ──
echo "Running test query..."
RESULT=$("$CLICKHOUSE" client --port 9000 -q "
SELECT id, count()
FROM dist_t1
WHERE id IN (SELECT id FROM dist_t2)
GROUP BY id
ORDER BY id
SETTINGS enable_optimize_predicate_expression = 1, distributed_product_mode = 'deny'
" 2>&1)
EXIT_CODE=$?

# ── Evaluate ──
if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "PASS: Bug is fixed — predicate pushdown does not create double-distributed subquery"
    echo "Result: $RESULT"
    exit 0
else
    if echo "$RESULT" | grep -q "DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED"; then
        echo ""
        echo "FAIL: Bug is present — predicate pushdown incorrectly creates double-distributed subquery"
        echo "Error: $RESULT"
        exit 1
    else
        echo ""
        echo "FAIL: Unexpected error: $RESULT"
        exit 1
    fi
fi
