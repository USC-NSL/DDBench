#!/usr/bin/env bash
# Reproduction and verification script for clickhouse-98079-keeper-addwatch
# Runs ClickHouse Keeper from source build, sends addWatch
# via zkCli.sh, and reports PASS/FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_NAME="clickhouse-98079-keeper-addwatch"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/${CASE_NAME}"
KEEPER="$WORK_DIR/src/build/programs/clickhouse"
ZK_CLI="$WORK_DIR/tools/apache-zookeeper-3.8.4-bin/bin/zkCli.sh"

echo "=== Reproducing ${CASE_NAME} ==="

# ── Cleanup from previous runs ──
PID_KEEPER=""
cleanup() {
    echo "Cleaning up..."
    [ -n "$PID_KEEPER" ] && kill "$PID_KEEPER" 2>/dev/null || true
    [ -n "$PID_KEEPER" ] && wait "$PID_KEEPER" 2>/dev/null || true
    rm -rf "$WORK_DIR/data"
}
trap cleanup EXIT

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$KEEPER" ]; then
    echo "ERROR: Keeper binary not found at $KEEPER. Run ./setup.sh first."
    exit 1
fi
if [ ! -f "$WORK_DIR/conf/keeper_config.xml" ]; then
    echo "ERROR: Config not found at $WORK_DIR/conf/keeper_config.xml. Run ./setup.sh first."
    exit 1
fi
if [ ! -f "$ZK_CLI" ]; then
    echo "ERROR: zkCli.sh not found at $ZK_CLI. Run ./setup.sh first."
    exit 1
fi
if ! command -v java &>/dev/null; then
    echo "ERROR: java is required for zkCli.sh but not installed."
    exit 1
fi

# Prepare fresh data directory
rm -rf "$WORK_DIR/data"
mkdir -p "$WORK_DIR/data/coordination/log" "$WORK_DIR/data/coordination/snapshots"
mkdir -p "$WORK_DIR/logs"

# ── Start Keeper ──
echo "Starting ClickHouse Keeper..."
"$KEEPER" keeper \
    --config-file="$WORK_DIR/conf/keeper_config.xml" \
    &>"$WORK_DIR/logs/keeper.log" 2>&1 &
PID_KEEPER=$!

# ── Wait for Keeper to be ready ──
echo "Waiting for Keeper to be ready..."
for i in $(seq 1 30); do
    if echo ruok | nc -w 2 localhost 2181 2>/dev/null | grep -q "imok"; then
        echo "Keeper is ready."
        break
    fi
    if ! kill -0 "$PID_KEEPER" 2>/dev/null; then
        echo "ERROR: Keeper process exited unexpectedly. Check $WORK_DIR/logs/keeper.log"
        exit 1
    fi
    sleep 1
done

# ── Create the /test znode using zkCli.sh ──
echo "Creating /test znode..."
"$ZK_CLI" -server localhost:2181 create /test "testdata" 2>&1 | tail -5 || true
sleep 1

# ── Try addWatch — this triggers the bug ──
echo "Sending addWatch /test..."
RESULT=$(echo "addWatch /test" | timeout 10 "$ZK_CLI" -server localhost:2181 2>&1 || true)

# ── Evaluate ──
if echo "$RESULT" | grep -q "CONNECTIONLOSS\|Connection refused\|KeeperException\|connection is not alive\|Disconnected\|EndOfStreamException"; then
    echo ""
    echo "FAIL: Bug is present — Keeper disconnects client on addWatch"
    exit 1
elif echo "$RESULT" | grep -q "Created\|PERSISTENT"; then
    echo ""
    echo "PASS: Bug is fixed — addWatch request handled correctly"
    exit 0
else
    # Check if the connection was lost by looking for error indicators
    if echo "$RESULT" | grep -q "Exception\|ERROR\|Lost"; then
        echo ""
        echo "FAIL: Bug is present — Keeper disconnects client on addWatch"
        echo "Output: $RESULT"
        exit 1
    else
        echo ""
        echo "PASS: Bug is fixed — addWatch request handled correctly"
        echo "Output: $RESULT"
        exit 0
    fi
fi
