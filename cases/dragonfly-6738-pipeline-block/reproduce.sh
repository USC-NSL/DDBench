#!/usr/bin/env bash
# Reproduction and verification script for dragonfly-6738-pipeline-block
# Two pipelines, each sent in one write on its own connection:
#   1. "SET mykey myval", "PING", "BLPOP nolist 5": the first reply must arrive
#      well before BLPOP's 5-second timeout.
#   2. Three "BRPOPLPUSH src dst 5" (as queue workers pipeline them); another
#      client then pushes one element to src: the reply carrying that element
#      must arrive promptly, not after the other pipelined pops time out.
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

BINARY="$WORK_DIR/build-dbg/dragonfly"
PORT=16738
DATA_DIR="$RUN_DIR/data"
SERVER_PID=""
# Reply deadlines (seconds). The blocking commands time out after 5 s, so a
# held-back reply arrives after >= 5 s (pipeline 1) or >= 10 s (pipeline 2).
MAX_FIRST_REPLY=2.0
MAX_WAKEUP_REPLY=2.5

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null && wait "$SERVER_PID" 2>/dev/null
    fi
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

rebuild_worktree
[ -x "$BINARY" ] || error "dragonfly binary not found at $BINARY (run setup first)"
command -v python3 >/dev/null || error "python3 not found in the image"
mkdir -p "$DATA_DIR"

echo "=== Reproducing dragonfly-6738-pipeline-block ==="

"$BINARY" --port "$PORT" --logtostderr --proactor_threads 2 \
    --dbfilename="" --dir "$DATA_DIR" > "$RUN_DIR/server.log" 2>&1 &
SERVER_PID=$!
wait_for_ping "$PORT" "$SERVER_PID" 60 || { tail -20 "$RUN_DIR/server.log"; fail "Dragonfly did not start serving"; }

# The client prints one "key value" line per measurement; the verdict is decided
# below from these protocol-level observations.
python3 - "$PORT" > "$RUN_DIR/measure.txt" <<'PY'
import socket, sys, time

port = int(sys.argv[1])

def connect():
    s = socket.create_connection(("127.0.0.1", port), timeout=30)
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    return s

def resp(*args):
    out = b"*%d\r\n" % len(args)
    for a in args:
        a = str(a).encode()
        out += b"$%d\r\n%s\r\n" % (len(a), a)
    return out

def first_chunk(sock):
    try:
        return sock.recv(4096)
    except socket.timeout:
        return b""

# Pipeline 1: two non-blocking commands followed by a blocking pop on an empty list.
s = connect()
t0 = time.monotonic()
s.sendall(b"SET mykey myval\r\nPING\r\nBLPOP nolist 5\r\n")
chunk = first_chunk(s)
print("p1_first_reply_s %.3f" % (time.monotonic() - t0))
print("p1_first_reply_ok %d" % (1 if chunk.startswith(b"+OK\r\n") else 0))
print("p1_first_reply_bytes %r" % chunk[:40])
s.close()

# Pipeline 2: three blocking pops on one connection, woken by a push from another client.
c = connect()
c.sendall(resp("BRPOPLPUSH", "src", "dst", 5) * 3)
time.sleep(1.0)
p = connect()
p.sendall(resp("RPUSH", "src", "hello"))
push_reply = first_chunk(p)
t_push = time.monotonic()
print("p2_push_ok %d" % (1 if push_reply.startswith(b":1\r\n") else 0))
print("p2_push_reply_bytes %r" % push_reply[:40])
chunk = first_chunk(c)
print("p2_wakeup_reply_s %.3f" % max(0.0, time.monotonic() - t_push))
print("p2_wakeup_reply_ok %d" % (1 if chunk.startswith(b"$5\r\nhello\r\n") else 0))
print("p2_wakeup_reply_bytes %r" % chunk[:40])
p.close()
c.close()
PY
PY_RC=$?
cat "$RUN_DIR/measure.txt"
[ "$PY_RC" -eq 0 ] || { tail -20 "$RUN_DIR/server.log"; kill -0 "$SERVER_PID" 2>/dev/null || fail "Dragonfly exited during the test"; error "the measuring client failed (exit $PY_RC)"; }

m() { awk -v k="$1" '$1 == k { print $2 }' "$RUN_DIR/measure.txt"; }
slower() { awk -v t="$1" -v lim="$2" 'BEGIN { exit !(t + 0 >= lim + 0) }'; }
P1_T=$(m p1_first_reply_s); P1_OK=$(m p1_first_reply_ok)
P2_PUSH=$(m p2_push_ok); P2_T=$(m p2_wakeup_reply_s); P2_OK=$(m p2_wakeup_reply_ok)
[ -n "$P1_T" ] && [ -n "$P2_T" ] || error "the measuring client produced no measurements"

problems=""
if [ "$P1_OK" != 1 ]; then
    problems="$problems; pipeline 1: the first reply was not +OK"
elif slower "$P1_T" "$MAX_FIRST_REPLY"; then
    problems="$problems; pipeline 1: the replies to SET/PING were held for ${P1_T}s (until the blocking BLPOP timed out)"
fi
if [ "$P2_PUSH" != 1 ]; then
    problems="$problems; pipeline 2: RPUSH from the second client did not return :1"
elif [ "$P2_OK" != 1 ]; then
    problems="$problems; pipeline 2: the first reply did not carry the pushed element"
elif slower "$P2_T" "$MAX_WAKEUP_REPLY"; then
    problems="$problems; pipeline 2: the reply carrying the pushed element arrived ${P2_T}s after the push (after the other pipelined pops timed out)"
fi

kill -0 "$SERVER_PID" 2>/dev/null || fail "Dragonfly exited during the test${problems}"
if [ -n "$problems" ]; then
    fail "Bug is present — replies on a pipelined connection are held back behind a blocking command${problems}"
fi
pass "Bug is fixed — replies before a pipelined blocking command arrive in ${P1_T}s, and a woken pipelined pop is answered ${P2_T}s after the push"
