#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-3148-namespace-delete
# Adds namespaces ns1 (token1) and ns2 (token2), then sets ns1's token to
# token2, and checks that ns2 still exists.
#
# Exit codes: 0 = PASS (bug fixed), 1 = FAIL (bug present, or the worktree does
# not build / the code under test does not start), 2 = ERROR (oracle or
# infrastructure problem; the verdict is inconclusive).
# ── Runs only inside the bench.sh reproduce container (BENCH_WORKDIR is set) ──
if [ -z "${BENCH_WORKDIR:-}" ]; then
    CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    [ -f "$REPO_ROOT/bench.sh" ] && exec bash "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
    echo "ERROR: run this oracle with ./bench.sh reproduce $CASE_NAME" >&2
    exit 2
fi
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$BENCH_WORKDIR"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ddbench.XXXXXX")"   # scratch space outside the worktree

pass()  { echo ""; echo "PASS: $*"; exit 0; }
fail()  { echo ""; echo "FAIL: $*"; exit 1; }
error() { echo ""; echo "ERROR: $*"; exit 2; }

# REBUILD.sh is the worktree's designated build entry point.
rebuild_worktree() {
    [ -f "$WORK_DIR/REBUILD.sh" ] || error "REBUILD.sh not found in $WORK_DIR (run setup first)"
    bash "$WORK_DIR/REBUILD.sh" || fail "the worktree does not build (REBUILD.sh exited non-zero)"
}

# ── Server liveness ──
wait_for_ping() {  # <port> <pid> [seconds]: succeed once the server answers PING
    local i
    for i in $(seq 1 $(( ${3:-30} * 4 ))); do
        kill -0 "$2" 2>/dev/null || return 1
        [ "$(timeout 2 redis-cli -p "$1" PING 2>/dev/null)" = "PONG" ] && return 0
        sleep 0.25
    done
    return 1
}
alive_and_responsive() {  # <port> <pid>
    kill -0 "$2" 2>/dev/null && [ "$(timeout 5 redis-cli -p "$1" PING 2>/dev/null)" = "PONG" ]
}


BINARY="$WORK_DIR/build/kvrocks"
PORT=13148
DATA_DIR="$RUN_DIR/data"
CONF_FILE="$RUN_DIR/kvrocks.conf"

rebuild_worktree

# Verify setup
if [ ! -x "$BINARY" ]; then
    error "binary not found at $BINARY (run setup first)"
fi

# Cleanup from previous runs
pkill -f "kvrocks.*--port $PORT" 2>/dev/null || true
pkill -f "kvrocks.*-c $CONF_FILE" 2>/dev/null || true
sleep 1
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR/logs"

echo "=== Reproducing kvrocks-3148-namespace-delete ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    rm -rf "$DATA_DIR"
    rm -f "$CONF_FILE"
}
trap cleanup EXIT

# Create config file with requirepass (needed for NAMESPACE commands)
cat > "$CONF_FILE" <<EOF
bind 0.0.0.0
port $PORT
dir $DATA_DIR
log-dir $DATA_DIR/logs
requirepass foobared
EOF

# Start Kvrocks
"$BINARY" -c "$CONF_FILE" > "$RUN_DIR/server.log" 2>&1 &
SERVER_PID=$!
ready=false
for _ in $(seq 1 120); do
    kill -0 "$SERVER_PID" 2>/dev/null || break
    [ "$(timeout 2 redis-cli -p "$PORT" -a foobared --no-auth-warning PING 2>/dev/null)" = "PONG" ] && { ready=true; break; }
    sleep 0.25
done
[ "$ready" = true ] || { tail -20 "$RUN_DIR/server.log"; fail "Kvrocks did not start serving"; }

# Create two namespaces with different tokens
echo "Adding namespace ns1 with token1..."
[ "$(redis-cli -p "$PORT" -a foobared --no-auth-warning NAMESPACE ADD ns1 token1 2>/dev/null)" = "OK" ] || fail "NAMESPACE ADD ns1 failed"
echo "Adding namespace ns2 with token2..."
[ "$(redis-cli -p "$PORT" -a foobared --no-auth-warning NAMESPACE ADD ns2 token2 2>/dev/null)" = "OK" ] || fail "NAMESPACE ADD ns2 failed"

echo "Current namespaces:"
redis-cli -p "$PORT" -a foobared --no-auth-warning NAMESPACE GET '*' 2>/dev/null

# Trigger the bug: set ns1's token to ns2's token (duplicate)
echo ""
echo "Sending: NAMESPACE SET ns1 token2 (duplicate token)"
redis-cli -p "$PORT" -a foobared --no-auth-warning NAMESPACE SET ns1 token2 2>/dev/null

# Check if ns2 still exists
echo ""
echo "Checking namespaces after SET:"
RESULT=$(redis-cli -p "$PORT" -a foobared --no-auth-warning NAMESPACE GET '*' 2>&1) || fail "NAMESPACE GET failed after the token change: $RESULT"
echo "$RESULT"

# Cleanup
kill "$SERVER_PID" 2>/dev/null
wait "$SERVER_PID" 2>/dev/null
rm -rf "$DATA_DIR"
rm -f "$CONF_FILE"

# Verdict
echo "$RESULT" | grep -qx "ns2" && pass "Bug is fixed — ns2 still exists after the token collision"
fail "Bug is present — ns2 disappeared when ns1 took over its token"
