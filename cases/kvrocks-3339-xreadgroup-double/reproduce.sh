#!/usr/bin/env bash
# Reproduction and verification script for kvrocks-3339-xreadgroup-double
#
# Detection principle (no byte-level pattern matching):
#   The RESP protocol contract is "one command sent => one top-level reply
#   frame read". After sending ONE XREADGROUP we parse exactly one RESP
#   top-level frame and then assert the server has no further bytes queued
#   on the socket (nothing in the parser's leftover buffer AND a brief
#   blocking recv times out). If any stray bytes appear, the server emitted
#   an extra frame and desynchronized the client — exactly what real
#   client libraries observe when they hit this bug.
#
# Race amplification:
#   - Stream/group start EMPTY (XGROUP CREATE ... $ MKSTREAM), so consumers
#     genuinely BLOCK instead of draining a backlog on the first iteration.
#   - Many consumers (NUM_CONSUMERS) share the same group. One XADD wakes
#     the group; at most one consumer claims the new entry and the rest
#     find results.empty() in OnWrite — that is the buggy code path.
#   - Persistent per-consumer connections mirror how real client libraries
#     would cascade-fail after a desync.

# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi

# ── Host fallback (no Docker) ──
set -uo pipefail

WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-3339-xreadgroup-double"
BINARY="$WORK_DIR/build/kvrocks"
PORT=13339
DATA_DIR="$WORK_DIR/kvrocks-3339-data"
DETECT_SCRIPT="$WORK_DIR/kvrocks-3339-detect.py"

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

pkill -f "kvrocks.*--port $PORT" 2>/dev/null || true
sleep 1
rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"

echo "=== Reproducing kvrocks-3339-xreadgroup-double ==="

cleanup() {
    if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null
        for _ in $(seq 1 20); do
            kill -0 "$SERVER_PID" 2>/dev/null || break
            sleep 0.25
        done
        kill -9 "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$DATA_DIR"
    rm -f "$DETECT_SCRIPT"
}
trap cleanup EXIT

"$BINARY" --port "$PORT" --dir "$DATA_DIR" --log-dir "$DATA_DIR" &>"$DATA_DIR/kvrocks_launch.log" &
SERVER_PID=$!

# Wait until the server is actually accepting connections (not just "alive").
# A bare sleep is fragile on slow CI runners; poll the port for up to 15s.
for _ in $(seq 1 60); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "ERROR: Kvrocks exited during startup. Log:"
        cat "$DATA_DIR/kvrocks_launch.log" 2>/dev/null | tail -20
        cat "$DATA_DIR"/kvrocks_*.log 2>/dev/null | tail -20
        exit 1
    fi
    if python3 -c "import socket;s=socket.socket();s.settimeout(0.3);
try:
    s.connect(('127.0.0.1',$PORT))
    s.close()
except Exception:
    exit(1)" 2>/dev/null; then
        break
    fi
    sleep 0.25
done

if ! python3 -c "import socket;s=socket.socket();s.settimeout(1);s.connect(('127.0.0.1',$PORT));s.close()" 2>/dev/null; then
    echo "ERROR: Kvrocks did not start listening on port $PORT within 15s. Log:"
    cat "$DATA_DIR/kvrocks_launch.log" 2>/dev/null | tail -20
    cat "$DATA_DIR"/kvrocks_*.log 2>/dev/null | tail -20
    exit 1
fi

cat > "$DETECT_SCRIPT" <<'PYEOF'
"""RESP-framing oracle for the XREADGROUP double-reply bug.

Oracle invariant (no byte-level pattern matching):
    On any RESP connection the server MUST emit exactly one top-level RESP
    frame per command it accepted. For a blocking XREADGROUP we send ONE
    command and then, with no further commands queued, expect the server to
    emit exactly ONE frame. If we find more bytes on the socket beyond the
    first correctly-framed reply, the server has desynchronized the
    connection — which is exactly what real client libraries observe.

Per iteration on each consumer connection:
    send  : XREADGROUP GROUP g c COUNT 1 BLOCK T STREAMS s >
    read  : parse exactly one RESP top-level frame
    check : after the frame, give the server a short grace window and verify
            the socket has NO further bytes (nothing in the parser's
            leftover buffer AND a brief blocking recv times out).

Race amplification: multiple consumers on the same group means one XADD
wakes them all, one claims the entry, the rest hit the empty-result path
in OnWrite — each such "loser" produces the buggy double frame. With N=16
consumers, one XADD yields ~15 amplified opportunities to detect.

Notes on design rejected alternatives:
    - Pipelining a follow-up command (e.g., PING) does NOT work reliably:
      Kvrocks suspends read-processing on a connection while a blocking
      command is outstanding, so the follow-up is only processed after the
      blocking command completes, and the timing interacts badly with the
      test.
    - Substring/regex matching on response bytes is fragile and misses the
      root invariant. We instead rely solely on RESP framing and a
      byte-count invariant.
"""
import socket
import sys
import threading
import time
import traceback

HOST = "127.0.0.1"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 13339
STREAM = "kv3339_stream"
GROUP = "kv3339_group"
NUM_CONSUMERS = 16
BLOCK_MS = 500
PRODUCER_INTERVAL = 0.02   # ~50 XADDs/sec
TEST_DURATION = 8.0        # seconds
MAX_EXAMPLES = 5
EXTRA_GRACE_MS = 150       # post-frame grace window to catch extra bytes
SOCK_TIMEOUT = BLOCK_MS / 1000.0 + 5.0


class RespError(Exception):
    pass


class RespReader:
    """Minimal, strict RESP2 reader. One read() call consumes exactly one top-level frame."""

    def __init__(self, sock):
        self.sock = sock
        self.buf = bytearray()

    def _fill_until(self, pred):
        while not pred():
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RespError("connection closed by server mid-frame")
            self.buf += chunk

    def _readline(self):
        self._fill_until(lambda: b"\r\n" in self.buf)
        idx = self.buf.index(b"\r\n")
        line = bytes(self.buf[:idx])
        del self.buf[: idx + 2]
        return line

    def _read_exact(self, n):
        self._fill_until(lambda: len(self.buf) >= n + 2)
        data = bytes(self.buf[:n])
        if self.buf[n : n + 2] != b"\r\n":
            raise RespError("bulk string not terminated by CRLF")
        del self.buf[: n + 2]
        return data

    def read(self):
        line = self._readline()
        if not line:
            raise RespError("empty line from server")
        t = chr(line[0])
        body = line[1:].decode("utf-8", errors="replace")
        if t in ("+", "-", ":"):
            return (t, body)
        if t == "$":
            n = int(body)
            if n < 0:
                return ("$", None)
            return ("$", self._read_exact(n))
        if t == "*":
            n = int(body)
            if n < 0:
                return ("*", None)
            return ("*", [self.read() for _ in range(n)])
        raise RespError(f"unknown RESP type byte: {t!r} (line={line!r})")


def encode(*args):
    out = bytearray()
    out += f"*{len(args)}\r\n".encode()
    for a in args:
        s = a.encode() if isinstance(a, str) else (a if isinstance(a, bytes) else str(a).encode())
        out += f"${len(s)}\r\n".encode()
        out += s
        out += b"\r\n"
    return bytes(out)


def connect():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(SOCK_TIMEOUT)
    s.connect((HOST, PORT))
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    return s


def simple_cmd(sock, reader, *args):
    sock.sendall(encode(*args))
    return reader.read()


def check_no_extra_bytes(sock, reader, grace_ms):
    """After consuming exactly one top-level frame, there must be no further
    bytes on the socket. Returns (has_extra, extra_bytes_for_diagnostics)."""
    if reader.buf:
        return True, bytes(reader.buf[:256])
    # Briefly wait; the bug emits both frames back-to-back, so any legit
    # extra bytes would arrive within milliseconds.
    sock.settimeout(grace_ms / 1000.0)
    try:
        extra = sock.recv(4096)
    except socket.timeout:
        sock.settimeout(SOCK_TIMEOUT)
        return False, b""
    sock.settimeout(SOCK_TIMEOUT)
    if extra:
        return True, extra[:256]
    # recv returning empty means EOF; treat as error upstream
    return True, b"<EOF>"


# --- Shared state ---
stop_evt = threading.Event()
state_lock = threading.Lock()
errors = []           # list of (consumer_id, iteration, description, frame_1, extra)
stats = {
    "iterations": 0,
    "entries_read": 0,
    "nil_unblocks": 0,  # *-1 from empty-result OnWrite path
    "block_timeouts": 0,  # $-1 from TimerCB
    "entries_produced": 0,
}


def record_error(cid, iter_i, desc, frame_1, extra):
    with state_lock:
        if len(errors) < 10_000:
            errors.append((cid, iter_i, desc, repr(frame_1)[:200], repr(extra)[:200]))
        stop_evt.set()


def is_valid_xreadgroup_frame_type(frame):
    # Any legitimate XREADGROUP reply is a single RESP frame:
    #   $-1   (BLOCK timeout, sent by TimerCB)
    #   *-1   (nil array — empty-result path in OnWrite)
    #   *N    (array with entries)
    return frame[0] in ("*", "$")


def consumer(cid):
    try:
        sock = connect()
        reader = RespReader(sock)
        name = f"c{cid}"
        iter_i = 0
        while not stop_evt.is_set():
            sock.sendall(encode(
                "XREADGROUP", "GROUP", GROUP, name,
                "COUNT", "1", "BLOCK", str(BLOCK_MS),
                "STREAMS", STREAM, ">",
            ))

            try:
                frame = reader.read()
            except Exception as e:
                record_error(cid, iter_i, f"failed to read XREADGROUP reply: {e}", None, None)
                return

            if not is_valid_xreadgroup_frame_type(frame):
                record_error(cid, iter_i,
                             f"XREADGROUP first frame type is unexpected ({frame[0]!r})",
                             frame, None)
                return

            has_extra, extra = check_no_extra_bytes(sock, reader, EXTRA_GRACE_MS)
            if has_extra:
                record_error(
                    cid, iter_i,
                    "server emitted extra bytes after the single XREADGROUP reply "
                    "(protocol desynced: client would misinterpret these as the reply "
                    "to the next command)",
                    frame, extra,
                )
                return

            # Track statistics on the (legitimate) reply type.
            with state_lock:
                stats["iterations"] += 1
                if frame == ("*", None):
                    stats["nil_unblocks"] += 1
                elif frame == ("$", None):
                    stats["block_timeouts"] += 1
                elif frame[0] == "*" and isinstance(frame[1], list):
                    stats["entries_read"] += 1

            iter_i += 1

    except Exception as e:
        record_error(cid, -1, f"consumer exception: {e}\n{traceback.format_exc()}", None, None)


def producer():
    try:
        sock = connect()
        reader = RespReader(sock)
        i = 0
        while not stop_evt.is_set():
            reply = simple_cmd(sock, reader, "XADD", STREAM, "*", "k", f"v{i}")
            if reply[0] not in ("$", "+"):
                # $<id>\r\n is the normal XADD reply. Anything else is a real error.
                record_error(-1, i, f"XADD returned unexpected reply: {reply!r}", reply, None)
                return
            with state_lock:
                stats["entries_produced"] += 1
            i += 1
            time.sleep(PRODUCER_INTERVAL)
    except Exception as e:
        record_error(-1, -1, f"producer exception: {e}", None, None)


# --- Setup: empty stream + empty group (consumers must truly block) ---
setup_sock = connect()
setup_reader = RespReader(setup_sock)
# DEL is harmless if the key doesn't exist.
simple_cmd(setup_sock, setup_reader, "DEL", STREAM)
# MKSTREAM + start-from-latest ($) means consumers see only entries produced
# AFTER they start reading, so every iteration genuinely BLOCKs.
try:
    r = simple_cmd(setup_sock, setup_reader, "XGROUP", "CREATE", STREAM, GROUP, "$", "MKSTREAM")
    if r[0] == "-":
        print(f"SETUP_ERROR: XGROUP CREATE failed: {r[1]}", flush=True)
        sys.exit(2)
except Exception as e:
    print(f"SETUP_ERROR: {e}", flush=True)
    sys.exit(2)
setup_sock.close()

# --- Run consumers and producer concurrently ---
threads = []
for cid in range(NUM_CONSUMERS):
    t = threading.Thread(target=consumer, args=(cid,), daemon=True)
    t.start()
    threads.append(t)

ptt = threading.Thread(target=producer, daemon=True)
ptt.start()

deadline = time.monotonic() + TEST_DURATION
while time.monotonic() < deadline and not stop_evt.is_set():
    time.sleep(0.05)
stop_evt.set()

for t in threads:
    t.join(timeout=3.0)
ptt.join(timeout=3.0)

# --- Report ---
with state_lock:
    print(
        f"iterations={stats['iterations']} "
        f"entries_read={stats['entries_read']} "
        f"nil_unblocks={stats['nil_unblocks']} "
        f"block_timeouts={stats['block_timeouts']} "
        f"entries_produced={stats['entries_produced']}",
        flush=True,
    )

    if errors:
        print(f"DESYNC_ERRORS={len(errors)}", flush=True)
        for cid, it, desc, f1, ex in errors[:MAX_EXAMPLES]:
            print(f"  [c{cid} iter={it}] {desc}", flush=True)
            print(f"    parsed_frame = {f1}", flush=True)
            print(f"    extra_bytes  = {ex}", flush=True)
        sys.exit(1)

# Sanity: we should have done SOMETHING in the time budget. An oracle that
# never exercised the code path would be useless.
if stats["iterations"] < 10 or stats["entries_produced"] < 5:
    print(
        "ORACLE_INSUFFICIENT: test ran but didn't exercise the code path "
        "enough to be a meaningful oracle.",
        flush=True,
    )
    sys.exit(2)

print("DESYNC_ERRORS=0", flush=True)
sys.exit(0)
PYEOF

python3 "$DETECT_SCRIPT" "$PORT"
DETECT_RC=$?

cleanup
trap - EXIT

echo ""
if [ "$DETECT_RC" -eq 0 ]; then
    echo "PASS: Bug is fixed — every XREADGROUP produced exactly one RESP frame per command."
    exit 0
elif [ "$DETECT_RC" -eq 2 ]; then
    echo "ERROR: Oracle could not reach the bug condition (setup or runtime issue above)."
    exit 2
else
    echo "FAIL: Bug is present — XREADGROUP BLOCK emitted an extra RESP frame, desynchronizing the client connection."
    exit 1
fi
