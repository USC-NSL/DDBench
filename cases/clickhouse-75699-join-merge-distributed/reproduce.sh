#!/usr/bin/env bash
# Reproduction and verification script for clickhouse-75699-join-merge-distributed
# Runs a ClickHouse process from source build, triggers the bug,
# and reports PASS/FAIL.
set -uo pipefail

CASE_NAME="clickhouse-75699-join-merge-distributed"
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

# ── Create tables and insert data (exact SQL from GitHub issue) ──
echo "Creating tables and inserting data..."
"$CLICKHOUSE" client --multiquery -q "
CREATE TABLE a (key UInt32, ID UInt32) ENGINE = Memory();
CREATE TABLE b (key UInt32, ID UInt32) ENGINE = Memory();
CREATE TABLE aa AS a ENGINE = Distributed('test_cluster', currentDatabase(), 'a');
CREATE TABLE m AS a ENGINE = Merge(currentDatabase(), 'a');
INSERT INTO a VALUES (1, 1), (2, 2);
INSERT INTO b VALUES (1, 1), (2, 2);
"

# ── Run the test query ──
echo "Running test query: SELECT * FROM m INNER JOIN b USING(key) WHERE ID = 1"
RESULT=$("$CLICKHOUSE" client -q "
SELECT * FROM m INNER JOIN b USING(key) WHERE ID = 1;
" 2>&1)
EXIT_CODE=$?

# ── Evaluate ──
if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "PASS: Bug is fixed — JOIN on Merge-over-Distributed works correctly"
    echo "Result: $RESULT"
    exit 0
else
    if echo "$RESULT" | grep -q "LOGICAL_ERROR"; then
        echo ""
        echo "FAIL: Bug is present — LOGICAL_ERROR on JOIN with Merge over Distributed table"
        echo "Error: $RESULT"
        exit 1
    else
        echo ""
        echo "FAIL: Unexpected error: $RESULT"
        exit 1
    fi
fi
