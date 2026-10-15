#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6687-replica-rdb-encoding
# Starts a master with tiered storage, loads large strings and hashes, waits for
# offloading, then starts a replica with REPLICAOF and checks that the full sync
# completes (link up) without RDB load errors in the replica's log.
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

BINARY="$WORK_DIR/build-opt/dragonfly"
MASTER_PORT=16687
REPLICA_PORT=16688
DATA_DIR="$RUN_DIR/data"
TIERED_PREFIX="$RUN_DIR/tiered"

rebuild_worktree
[ -x "$BINARY" ] || error "dragonfly binary not found at $BINARY (run setup first)"
mkdir -p "$DATA_DIR/master" "$DATA_DIR/replica"

echo "=== Reproducing dragonfly-6687-replica-rdb-encoding ==="

cleanup() {
    [ -n "${MASTER_PID:-}" ] && kill "$MASTER_PID" 2>/dev/null && wait "$MASTER_PID" 2>/dev/null
    [ -n "${REPLICA_PID:-}" ] && kill "$REPLICA_PID" 2>/dev/null && wait "$REPLICA_PID" 2>/dev/null
}
trap cleanup EXIT

echo "Starting master on port $MASTER_PORT with tiered storage..."
"$BINARY" --port "$MASTER_PORT" --logtostderr \
    --dbfilename="" --dir "$DATA_DIR/master" \
    --tiered_prefix="$TIERED_PREFIX" \
    --tiered_offload_threshold=1.0 \
    --serialization_max_chunk_size=64000 \
    --maxmemory=512mb > "$DATA_DIR/master.log" 2>&1 &
MASTER_PID=$!
wait_for_ping "$MASTER_PORT" "$MASTER_PID" 60 || { tail -20 "$DATA_DIR/master.log"; fail "master did not start serving"; }

echo "Loading data (large strings + hashes)..."
timeout 300 redis-cli -p "$MASTER_PORT" DEBUG POPULATE 200000 key 3000 >/dev/null 2>&1
timeout 300 redis-cli -p "$MASTER_PORT" DEBUG POPULATE 200 hash 70 RAND TYPE HASH ELEMENTS 900 >/dev/null 2>&1
DBSIZE=$(timeout 10 redis-cli -p "$MASTER_PORT" DBSIZE 2>/dev/null | tr -d '\r')
echo "Master DBSIZE: ${DBSIZE:-?}"
[ "${DBSIZE:-0}" -ge 200200 ] 2>/dev/null || error "data load did not complete on the master (DBSIZE=${DBSIZE:-none}); trigger not established"

echo "Waiting 15 seconds for tiered offloading..."
sleep 15
alive_and_responsive "$MASTER_PORT" "$MASTER_PID" || fail "master stopped responding during offloading"

echo "Starting replica on port $REPLICA_PORT..."
"$BINARY" --port "$REPLICA_PORT" --logtostderr \
    --dbfilename="" --dir "$DATA_DIR/replica" \
    --maxmemory=1024mb > "$DATA_DIR/replica.log" 2>&1 &
REPLICA_PID=$!
wait_for_ping "$REPLICA_PORT" "$REPLICA_PID" 60 || { tail -20 "$DATA_DIR/replica.log"; fail "replica did not start serving"; }

echo "Initiating replication: REPLICAOF localhost $MASTER_PORT"
[ "$(timeout 10 redis-cli -p "$REPLICA_PORT" REPLICAOF localhost "$MASTER_PORT" 2>/dev/null | tr -d '\r')" = "OK" ] \
    || fail "REPLICAOF was not accepted"

echo "Waiting for sync (up to 45 seconds)..."
LINK_STATUS=""
for _ in $(seq 1 45); do
    sleep 1
    LINK_STATUS=$(timeout 5 redis-cli -p "$REPLICA_PORT" INFO replication 2>/dev/null | grep master_link_status | tr -d '\r')
    echo "$LINK_STATUS" | grep -q ":up" && break
done
sleep 2
# The replica's RDB loader logs these when it receives a stream it cannot parse
# (the upstream regression test fails on the first message).
LOAD_ERRORS=$(grep -cE "Internal error when loading RDB|Unknown RDB string encoding" "$DATA_DIR/replica.log" 2>/dev/null)
echo "Replica: ${LINK_STATUS:-<no answer>}; RDB load errors in the replica log: ${LOAD_ERRORS:-0}"
grep -m3 -E "Internal error when loading RDB|Unknown RDB string encoding" "$DATA_DIR/replica.log" 2>/dev/null

if [ "${LOAD_ERRORS:-0}" -gt 0 ]; then
    fail "Bug is present — the replica hit RDB load errors during the full sync"
fi
if echo "$LINK_STATUS" | grep -q ":up"; then
    pass "Bug is fixed — the replica completed the full sync without RDB load errors (${LINK_STATUS})"
fi
fail "Bug is present — the replica did not complete the full sync (${LINK_STATUS:-no answer})"
