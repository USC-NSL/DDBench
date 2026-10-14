#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-3356-replication-wal
# Starts a Kvrocks master + replica, freezes the replica (SIGSTOP) so it stops
# consuming the replication stream while its TCP connection stays open, writes
# enough data to fill the master's socket buffers, then checks whether the
# master ever detaches the stuck replica. Reports PASS/FAIL.
#   FAIL (exit 1): master keeps the stalled replica attached for the whole
#                  observation window.
#   PASS (exit 0): master detaches the stalled replica within the window and
#                  replication recovers once the replica resumes.
#   ERROR (exit 2): the stall could not be established (inconclusive). Failures
#                  of the server itself (won't start, never syncs) are FAIL.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-3356-replication-wal"
BINARY="$WORK_DIR/build/kvrocks"
MASTER_PORT=13356
REPLICA_PORT=13357
RUN_DIR="$WORK_DIR/kvrocks-3356-run"
MASTER_DIR="$RUN_DIR/master"
REPLICA_DIR="$RUN_DIR/replica"
# How long the master is given to detach a stalled replica. Generous on purpose:
# any reasonable detection delay (up to ~60s, cf. Redis repl-timeout) must PASS.
STALL_WINDOW="${STALL_WINDOW:-90}"
# Data pushed while the replica is frozen: far more than the loopback socket buffers
# (tcp_wmem max 4MB + tcp_rmem max 6MB by default).
FILL_KEYS=256
FILL_VALUE_BYTES=262144

MASTER_PID=""
REPLICA_PID=""
TRICKLE_PID=""

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 2
fi

cleanup() {
    [ -n "$TRICKLE_PID" ] && kill "$TRICKLE_PID" 2>/dev/null
    # A SIGSTOPped process only dies on SIGKILL or after SIGCONT, and a master
    # with a stalled replica may not shut down cleanly -- so kill hard.
    for pid in $REPLICA_PID $MASTER_PID; do
        kill -CONT "$pid" 2>/dev/null
        kill -9 "$pid" 2>/dev/null
    done
    wait 2>/dev/null
    rm -rf "$RUN_DIR"
}
trap cleanup EXIT

rc() {  # rc <port> <args...>
    local port=$1; shift
    timeout 5 redis-cli -p "$port" "$@" 2>/dev/null
}

info_field() {  # info_field <port> <field>
    rc "$1" INFO replication | tr -d '\r' | awk -F: -v k="$2" '$1 == k {print $2}'
}

active_slaves() {  # replicas the master currently lists as attached; -1 if INFO fails
    local info
    info=$(rc "$MASTER_PORT" INFO replication | tr -d '\r')
    if ! grep -q '^connected_slaves:' <<<"$info"; then echo -1; return; fi
    grep -c '^slave[0-9]*:' <<<"$info"
}

alive() { kill -0 "$1" 2>/dev/null; }

# Print "<replica_local_port> <master_tx_queue_bytes>" for the replica's
# replication connection, or nothing if that connection no longer exists.
repl_conn_state() {
    python3 - "$REPLICA_PID" "$MASTER_PORT" <<'PY'
import os, sys
pid, mport = sys.argv[1], int(sys.argv[2])
inodes = set()
try:
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            link = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        if link.startswith("socket:["):
            inodes.add(link[8:-1])
except OSError:
    sys.exit(0)
rows = []
for path in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(path) as f:
            next(f)
            rows += [l.split() for l in f]
    except OSError:
        pass
port = lambda addr: int(addr.rsplit(":", 1)[1], 16)
# replica side: ESTABLISHED socket owned by the replica, connected to the master port
eph = next((port(r[1]) for r in rows if r[9] in inodes and r[3] == "01" and port(r[2]) == mport), None)
if eph is None:
    sys.exit(0)
for r in rows:
    if port(r[1]) == mport and port(r[2]) == eph and r[3] == "01":
        print(eph, int(r[4].split(":")[0], 16))
        break
PY
}

dump_logs() {
    echo "--- master log (replication-related, last 10 lines) ---"
    grep -haiE "slave|replica|timeout|WAL" "$MASTER_DIR"/kvrocks*.log 2>/dev/null | cut -c1-200 | tail -10
}

# ── Fresh start ──
pkill -9 -f "kvrocks.*$RUN_DIR" 2>/dev/null || true
rm -rf "$RUN_DIR"
mkdir -p "$MASTER_DIR" "$REPLICA_DIR"

cat > "$RUN_DIR/master.conf" <<EOF
bind 127.0.0.1
port $MASTER_PORT
dir $MASTER_DIR
log-dir $MASTER_DIR
EOF
cat > "$RUN_DIR/replica.conf" <<EOF
bind 127.0.0.1
port $REPLICA_PORT
dir $REPLICA_DIR
log-dir $REPLICA_DIR
slaveof 127.0.0.1 $MASTER_PORT
EOF

echo "=== Reproducing kvrocks-3356-replication-wal ==="

echo "Starting master on port $MASTER_PORT..."
"$BINARY" -c "$RUN_DIR/master.conf" &>/dev/null &
MASTER_PID=$!
for _ in $(seq 1 30); do rc "$MASTER_PORT" PING | grep -q PONG && break; sleep 0.5; done
if ! rc "$MASTER_PORT" PING | grep -q PONG; then
    echo "FAIL: Bug is present — master failed to start"; exit 1
fi

echo "Starting replica on port $REPLICA_PORT..."
"$BINARY" -c "$RUN_DIR/replica.conf" &>/dev/null &
REPLICA_PID=$!

# ── Phase 1: healthy replication ──
TOKEN="init-$RANDOM-$$"
rc "$MASTER_PORT" SET oracle:sentinel "$TOKEN" >/dev/null
synced=0
for _ in $(seq 1 60); do
    if [ "$(info_field "$REPLICA_PORT" master_link_status)" = "up" ] \
       && [ "$(rc "$REPLICA_PORT" GET oracle:sentinel)" = "$TOKEN" ] \
       && [ "$(active_slaves)" -ge 1 ]; then
        synced=1; break
    fi
    sleep 0.5
done
if [ "$synced" -ne 1 ]; then
    echo "FAIL: Bug is present — replication never became healthy (replica not synced before the stall)"
    rc "$MASTER_PORT" INFO replication | tr -d '\r' | grep -E "connected_slaves|^slave"
    exit 1
fi
echo "Replication healthy: $(rc "$MASTER_PORT" INFO replication | tr -d '\r' | grep '^slave0:')"

# ── Phase 2: replica stops consuming, connection stays open ──
echo "Freezing replica (SIGSTOP) -- it stops reading, but its kernel keeps the TCP connection alive..."
kill -STOP "$REPLICA_PID"

echo "Writing $((FILL_KEYS * FILL_VALUE_BYTES / 1048576))MB to master to fill the replication socket buffers..."
python3 - "$FILL_KEYS" "$FILL_VALUE_BYTES" <<'PY' | timeout 120 redis-cli -p "$MASTER_PORT" --pipe >/dev/null 2>&1
import sys
n, size = int(sys.argv[1]), int(sys.argv[2])
val = b"x" * size
out = sys.stdout.buffer
for i in range(n):
    key = b"oracle:fill:%d" % i
    out.write(b"*3\r\n$3\r\nSET\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n" % (len(key), key, size, val))
PY

# Confirm the stream is actually stalled: the master's send queue on the
# replication connection is non-empty. (Or the master already dropped the
# replica -- detaching very quickly is a legitimate outcome.)
stall=""
for _ in $(seq 1 20); do
    if [ "$(active_slaves)" -eq 0 ]; then stall="detached"; break; fi
    state=$(repl_conn_state)
    if [ -n "$state" ] && [ "${state#* }" -gt 0 ]; then stall="$state"; break; fi
    sleep 0.5
done
if [ -z "$stall" ]; then
    echo "ERROR: Could not establish a stalled replication stream (replica connection: '${state:-none}')."
    exit 2
fi
if [ "$stall" != "detached" ]; then
    echo "Stall established: master->replica(port ${stall% *}) send queue = ${stall#* } bytes"
fi

# Keep a light write load on the master, as in production.
( i=0; while :; do rc "$MASTER_PORT" SET "oracle:trickle:$i" "$i" >/dev/null; i=$((i + 1)); sleep 0.2; done ) &
TRICKLE_PID=$!

# ── Phase 3: does the master ever give up on the stuck replica? ──
detached_after=""
if [ "$stall" = "detached" ]; then
    detached_after=0
else
    echo "Observing master for up to ${STALL_WINDOW}s..."
    for t in $(seq 1 "$STALL_WINDOW"); do
        sleep 1
        if ! alive "$MASTER_PID"; then
            echo ""
            echo "FAIL: Bug is present — master process died while the replica was stalled"
            exit 1
        fi
        if [ "$(active_slaves)" -eq 0 ]; then detached_after=$t; break; fi
        if [ $((t % 15)) -eq 0 ]; then
            state=$(repl_conn_state)
            echo "  ${t}s: replica still attached, master send queue = ${state#* } bytes, $(info_field "$MASTER_PORT" connected_slaves) connected_slaves"
        fi
    done
fi

kill "$TRICKLE_PID" 2>/dev/null; wait "$TRICKLE_PID" 2>/dev/null; TRICKLE_PID=""

if [ -z "$detached_after" ]; then
    state=$(repl_conn_state)
    dump_logs
    echo ""
    echo "FAIL: Bug is present — master kept a stalled replica attached for ${STALL_WINDOW}s"
    echo "      (send queue stuck at ${state#* } bytes, nothing logged, replica never detached)"
    exit 1
fi
echo "Master detached the stalled replica after ~${detached_after}s."
dump_logs

# ── Phase 4: replication must recover once the replica resumes ──
echo "Resuming replica (SIGCONT) and checking that replication recovers..."
kill -CONT "$REPLICA_PID"
TOKEN="final-$RANDOM-$$"
rc "$MASTER_PORT" SET oracle:sentinel "$TOKEN" >/dev/null
recovered=0
for _ in $(seq 1 180); do
    if [ "$(info_field "$REPLICA_PORT" master_link_status)" = "up" ] \
       && [ "$(rc "$REPLICA_PORT" GET oracle:sentinel)" = "$TOKEN" ]; then
        recovered=1; break
    fi
    sleep 0.5
done
if [ "$recovered" -ne 1 ]; then
    dump_logs
    echo ""
    echo "FAIL: Master detached the stalled replica, but replication did not recover within 90s after it resumed"
    exit 1
fi

echo ""
echo "PASS: Bug is fixed — master detached the stalled replica after ~${detached_after}s and replication recovered"
exit 0
