#!/usr/bin/env bash
# Reproduction and verification script for <case-name>
# Starts the server, sends the trigger, and checks that the process survived and
# still answers.
# TODO: one line naming the trigger in observable terms.
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
# TODO: adjust the readiness probe if the server does not speak RESP (curl, nc ...).
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

BINARY="$WORK_DIR/BINARY_PATH"
PORT=TODO_PORT                    # convention: 1<issue#>
DATA_DIR="$RUN_DIR/data"
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; fi
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

rebuild_worktree
[ -x "$BINARY" ] || error "binary not found at $BINARY (run setup first)"
mkdir -p "$DATA_DIR"

echo "=== Reproducing <case-name> ==="

# ── Start the server (logs go to $RUN_DIR, never into the worktree) ──
"$BINARY" --port "$PORT" --dir "$DATA_DIR" > "$RUN_DIR/server.log" 2>&1 &
SERVER_PID=$!
if ! wait_for_ping "$PORT" "$SERVER_PID" 60; then
    tail -20 "$RUN_DIR/server.log"
    fail "the server did not start serving"
fi

# ── Trigger ──
echo "Sending trigger ..."
# TODO: send the commands/requests that trigger the crash, with bounded client calls:
#   timeout 10 redis-cli -p "$PORT" <command> 2>&1 | head -3
# TODO: confirm the trigger was delivered (the client got a reply or the connection
# was reset). If it never reached the server: error "trigger not delivered (...)"
sleep 1

# ── Verdict: the server must still be running AND answering ──
if alive_and_responsive "$PORT" "$SERVER_PID"; then
    pass "Bug is fixed — the server survived the trigger and still answers"
fi
if kill -0 "$SERVER_PID" 2>/dev/null; then
    fail "the server is running but no longer answers after the trigger"
fi
wait "$SERVER_PID"; EXIT_CODE=$?; SERVER_PID=""
tail -15 "$RUN_DIR/server.log"
fail "Bug is present — the server crashed on the trigger (exit code $EXIT_CODE)"
