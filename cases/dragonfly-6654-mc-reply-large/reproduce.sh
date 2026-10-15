#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6654-mc-reply-large
# Stores a 16000-byte value through the Redis port and reads it back with a
# memcached meta get (mg ... v), then checks that the server survived.
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

BINARY="$WORK_DIR/build-dbg/dragonfly"
PORT=16654
MC_PORT=21654
DATA_DIR="$RUN_DIR/data"

rebuild_worktree
[ -x "$BINARY" ] || error "dragonfly binary not found at $BINARY (run setup first)"
mkdir -p "$DATA_DIR"

echo "=== Reproducing dragonfly-6654-mc-reply-large ==="

cleanup() {
    [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
}
trap cleanup EXIT

"$BINARY" --port "$PORT" --memcached_port="$MC_PORT" --max_bulk_len=1048576 --logtostderr --proactor_threads 1 \
    --dbfilename="" --dir "$DATA_DIR" > "$RUN_DIR/server.log" 2>&1 &
SERVER_PID=$!
if ! wait_for_ping "$PORT" "$SERVER_PID" 60; then
    tail -20 "$RUN_DIR/server.log"
    fail "Dragonfly did not start serving"
fi

echo "Sending: SET bigkey (16000 bytes) via Redis, then 'mg bigkey v' via memcached"
LARGE_VALUE=$(python3 -c "print('A' * 16000)")
[ "$(timeout 10 redis-cli -p "$PORT" SET bigkey "$LARGE_VALUE" 2>/dev/null)" = "OK" ] \
    || fail "SET of the 16000-byte value did not succeed"
printf 'mg bigkey v\r\nquit\r\n' | timeout 10 nc -q 2 127.0.0.1 "$MC_PORT" > "$RUN_DIR/mc.out" 2>&1 || true
head -c 120 "$RUN_DIR/mc.out"; echo
sleep 1

# Verdict: the server must still be running AND answering.
if alive_and_responsive "$PORT" "$SERVER_PID"; then
    pass "Bug is fixed — the server survived a memcached meta get of a large value"
fi
if kill -0 "$SERVER_PID" 2>/dev/null; then
    fail "Dragonfly is running but no longer answers PING after the trigger"
fi
wait "$SERVER_PID"; EXIT_CODE=$?; SERVER_PID=
tail -15 "$RUN_DIR/server.log"
fail "Bug is present — the server crashed on a memcached meta get of a large value (exit code $EXIT_CODE)"
