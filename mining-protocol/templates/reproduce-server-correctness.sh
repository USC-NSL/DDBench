#!/usr/bin/env bash
# Reproduction and verification script for <case-name>
# Starts a two-node setup, establishes the baseline (replication up, data in sync),
# triggers the bug condition, and checks the data the nodes return.
# TODO: one line on the scenario and what is checked, in observable terms.
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

# ── Helpers ──
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
# Poll a condition (a shell command) for up to <seconds>; succeed once it holds.
wait_until() {  # <seconds> <command...>
    local deadline=$(( $(date +%s) + $1 )); shift
    until "$@"; do
        [ "$(date +%s)" -ge "$deadline" ] && return 1
        sleep 0.5
    done
}

BINARY="$WORK_DIR/BINARY_PATH"
PORT1=TODO_PORT1                  # convention: 1<issue#> and 1<issue#>+1
PORT2=TODO_PORT2
NODE1_DIR="$RUN_DIR/node1"
NODE2_DIR="$RUN_DIR/node2"
NODE1_PID=""
NODE2_PID=""

stop_node() {  # <pid>
    [ -n "$1" ] || return 0
    kill "$1" 2>/dev/null
    wait "$1" 2>/dev/null
}
cleanup() {
    stop_node "$NODE1_PID"
    stop_node "$NODE2_PID"
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

rebuild_worktree
[ -x "$BINARY" ] || error "binary not found at $BINARY (run setup first)"
mkdir -p "$NODE1_DIR" "$NODE2_DIR"

echo "=== Reproducing <case-name> ==="

# ── Step 1: start both nodes (logs in $RUN_DIR) ──
# TODO: start the servers with the configuration the scenario needs.
"$BINARY" --port "$PORT1" --dir "$NODE1_DIR" > "$RUN_DIR/node1.log" 2>&1 &
NODE1_PID=$!
wait_for_ping "$PORT1" "$NODE1_PID" 60 || { tail -20 "$RUN_DIR/node1.log"; fail "node 1 did not start serving"; }
"$BINARY" --port "$PORT2" --dir "$NODE2_DIR" > "$RUN_DIR/node2.log" 2>&1 &
NODE2_PID=$!
wait_for_ping "$PORT2" "$NODE2_PID" 60 || { tail -20 "$RUN_DIR/node2.log"; fail "node 2 did not start serving"; }

# ── Step 2: establish the baseline ──
# TODO: set up the cluster/replication topology, write initial data, and wait until
# it is visible on both nodes (wait_until 60 <check>). If the code under test never
# reaches the baseline state, that is FAIL:
#   wait_until 60 replication_is_up || fail "replication link did not come up"

# ── Step 3: trigger the bug condition ──
# TODO: trigger it, then confirm the trigger actually took effect (fault injected,
# node really down, connection really stalled). If not, the run is inconclusive:
#   error "trigger not established (<what was observed>)"
# Never hide trigger errors with 2>/dev/null or || true. No sudo; prefer
# process-level faults (SIGSTOP/SIGCONT, kill, a pausable proxy) over iptables/tc.

# ── Step 4: check data correctness ──
# TODO: read back what a correct system must return, with a generous window so
# alternative fixes pass, and compare against the expected values.
EXPECTED="TODO_EXPECTED"
ACTUAL="TODO_ACTUAL"
echo "Read back: '$ACTUAL' (expected '$EXPECTED')"

if [ "$ACTUAL" = "$EXPECTED" ]; then
    pass "Bug is fixed — PASS_DESCRIPTION"
fi
fail "Bug is present — FAIL_DESCRIPTION"
