#!/usr/bin/env bash
# Reproduction and verification script for CASE_NAME
# Starts a server cluster, triggers the bug condition, and checks data correctness.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/CASE_NAME"
BINARY="$WORK_DIR/BINARY_PATH"
PORT1=TODO_PORT1
PORT2=TODO_PORT2
DATA_DIR1="$WORK_DIR/CASE_NAME-node1"
DATA_DIR2="$WORK_DIR/CASE_NAME-node2"

# ── Rebuild if source changed ──
if [ -f "$WORK_DIR/REBUILD.sh" ] && ! bash "$WORK_DIR/REBUILD.sh"; then
    echo "FAIL: Bug is present — code under test does not build"; exit 1
fi

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 2
fi

NODE1_PID=""
NODE2_PID=""

cleanup() {
    echo "Cleaning up..."
    kill "$NODE1_PID" "$NODE2_PID" 2>/dev/null || true
    wait "$NODE1_PID" "$NODE2_PID" 2>/dev/null || true
    rm -rf "$DATA_DIR1" "$DATA_DIR2"
}
trap cleanup EXIT

# Cleanup from previous runs
pkill -f "BINARY_NAME.*$PORT1\|BINARY_NAME.*$PORT2" 2>/dev/null || true
sleep 1
rm -rf "$DATA_DIR1" "$DATA_DIR2"
mkdir -p "$DATA_DIR1" "$DATA_DIR2"

echo "=== Reproducing CASE_NAME ==="

# ── Helper: wait for server to accept connections ──
wait_for_port() {
    local port=$1 label=$2 timeout=30
    echo "Waiting for $label on port $port..."
    for i in $(seq 1 $timeout); do
        # TODO: Adjust readiness check for your server (redis-cli PING, curl, nc)
        if redis-cli -p "$port" PING 2>/dev/null | grep -qi pong; then
            echo "$label is ready."
            return 0
        fi
        sleep 1
    done
    echo "$label did not become ready within ${timeout}s."
    return 1
}

# ── Step 1: Start node 1 ──
echo "Step 1: Starting node 1..."
# TODO: Start server with appropriate config
"$BINARY" --port "$PORT1" --dir "$DATA_DIR1" &>/dev/null &
NODE1_PID=$!
if ! wait_for_port "$PORT1" "Node 1"; then echo "FAIL: Bug is present — node 1 failed to start"; exit 1; fi

# ── Step 2: Start node 2 ──
echo "Step 2: Starting node 2..."
# TODO: Start second node, set up replication
"$BINARY" --port "$PORT2" --dir "$DATA_DIR2" &>/dev/null &
NODE2_PID=$!
if ! wait_for_port "$PORT2" "Node 2"; then echo "FAIL: Bug is present — node 2 failed to start"; exit 1; fi

# ── Step 3: TODO: Set up cluster/replication topology ──

# ── Step 4: TODO: Write initial data and verify replication ──

# ── Step 5: TODO: Trigger the bug condition ──
# TODO: Confirm the trigger actually took effect (fault injected, request delivered,
# node really down, connection really stalled). If not, the run is inconclusive:
#   echo "ERROR: trigger not established (<what was observed>)"; exit 2
# Never let a failed trigger fall through to the verdict, and don't hide trigger
# errors with 2>/dev/null or || true. No sudo: bench.sh reproduce runs as root,
# agents run as the non-root `bench` user. Prefer process-level faults (SIGSTOP,
# kill, a pausable proxy) over iptables/tc.

# ── Step 6: TODO: Check data correctness ──

# ── Verdict ──
BUGS_FOUND=0
# TODO: Add correctness checks
# if [ "$ACTUAL" != "$EXPECTED" ]; then BUGS_FOUND=1; fi

echo ""
if [ "$BUGS_FOUND" -eq 1 ]; then
    echo "FAIL: Bug is present — FAIL_DESCRIPTION"
    exit 1
else
    echo "PASS: Bug is fixed — PASS_DESCRIPTION"
    exit 0
fi
