# Reproduce: Dragonfly #6738

All commands run inside `./bench.sh shell dragonfly-6738-pipeline-block`, from the worktree `/workspace/src`.

## Step 1: Build and start Dragonfly

```bash
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug -DWITH_AWS=OFF && (cd build-dbg && ninja dragonfly)
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 2 --dbfilename="" &
until [ "$(redis-cli -p 6379 PING 2>/dev/null)" = PONG ]; do sleep 0.2; done
```

## Step 2: Pipeline non-blocking commands in front of a blocking one

Send three commands in one write and time when the first reply arrives:

```bash
python3 - <<'PY'
import socket, time
s = socket.create_connection(("127.0.0.1", 6379))
t0 = time.monotonic()
s.sendall(b"SET mykey myval\r\nPING\r\nBLPOP nolist 5\r\n")
first = s.recv(4096)
print(f"first reply after {time.monotonic() - t0:.2f}s: {first!r}")
PY
```

## Step 3: Pipeline several blocking pops and wake the first one

This is the pattern the queue workers use: one connection pipelines three `BRPOPLPUSH`, and a second client pushes one element.

```bash
python3 - <<'PY'
import socket, time
def resp(*a):
    return b"*%d\r\n" % len(a) + b"".join(b"$%d\r\n%s\r\n" % (len(x), x) for x in (str(v).encode() for v in a))
worker = socket.create_connection(("127.0.0.1", 6379))
worker.sendall(resp("BRPOPLPUSH", "src", "dst", 5) * 3)
time.sleep(1)
producer = socket.create_connection(("127.0.0.1", 6379))
producer.sendall(resp("RPUSH", "src", "hello"))
print("RPUSH ->", producer.recv(64))
t_push = time.monotonic()
first = worker.recv(4096)
print(f"worker got its first reply {time.monotonic() - t_push:.2f}s after the push: {first!r}")
PY
```

The push can also come from a Lua script, as in the original report (`redis-cli -p 6379 EVAL "return redis.call('RPUSH', KEYS[1], ARGV[1])" 1 src hello`). The delay is the same.

## Expected result (bug present)

- Step 2: the first reply arrives after about 5 s (when `BLPOP` times out), and `+OK`, `+PONG` and the `BLPOP` nil reply arrive together.
- Step 3: `RPUSH` returns `:1` at once, but the worker receives `$5 hello` about 10 s after the push, together with the nil replies of the two other pops.

Sent one at a time (for example with plain `redis-cli`), the same commands get their replies immediately.

## Cleanup

```bash
redis-cli -p 6379 SHUTDOWN NOSAVE 2>/dev/null || pkill -f "dragonfly --port 6379"
```

## Oracle verdict

`./bench.sh reproduce dragonfly-6738-pipeline-block` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): for `SET mykey myval`, `PING`, `BLPOP nolist 5` sent in one write, the first reply is not `+OK` or arrives 2.0 s or more after the send; or, for three pipelined `BRPOPLPUSH src dst 5` woken by `RPUSH src hello` from a second client, `RPUSH` does not return `:1`, or the worker's first reply is not `hello` or arrives 2.5 s or more after the push. A worktree that does not build, or a Dragonfly server that does not answer `PING` within 60 s of starting or exits during the test, is also FAIL.
- **PASS** (exit 0): the first reply of each pipeline (`+OK`, then `hello`) is correct and arrives within its deadline (under 2.0 s after the send, under 2.5 s after the push).
- **ERROR** (exit 2): `REBUILD.sh`, the built `build-dbg/dragonfly` binary or `python3` is missing, or the measuring client fails or produces no measurements while the server is still running.
