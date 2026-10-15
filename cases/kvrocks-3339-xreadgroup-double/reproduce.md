# Reproduce: Kvrocks #3339

## Prerequisites
Run inside `./bench.sh shell kvrocks-3339-xreadgroup-double`, from `/workspace/src`, and start a Kvrocks instance:

```bash
mkdir -p /tmp/kvrocks-data
./build/kvrocks --port 6666 --dir /tmp/kvrocks-data --log-dir /tmp/kvrocks-logs &
```

## Step 1: Create stream and consumer group

```bash
redis-cli -p 6666 XADD mystream '*' init init
redis-cli -p 6666 XGROUP CREATE mystream mygroup 0
```

## Step 2: Start multiple blocking consumers

In multiple terminals (or background processes), run blocking XREADGROUP:
```bash
# Terminal 1
redis-cli -p 6666 XREADGROUP GROUP mygroup consumer1 BLOCK 10000 COUNT 1 STREAMS mystream '>'

# Terminal 2
redis-cli -p 6666 XREADGROUP GROUP mygroup consumer2 BLOCK 10000 COUNT 1 STREAMS mystream '>'

# Terminal 3
redis-cli -p 6666 XREADGROUP GROUP mygroup consumer3 BLOCK 10000 COUNT 1 STREAMS mystream '>'
```

## Step 3: Concurrent XADD

In another terminal, rapidly add entries:
```bash
for i in $(seq 1 100); do
    redis-cli -p 6666 XADD mystream '*' key "value$i"
    sleep 0.01
done
```

## Step 4: Scripted reproduction

This script needs the Python `redis` package, which is not preinstalled in the image.

```python
import redis
import threading
import time

r = redis.Redis(port=6666)
r.xadd('teststream', {'init': 'init'})
r.xgroup_create('teststream', 'testgroup', id='0', mkstream=True)

errors = []

def consumer(name):
    c = redis.Redis(port=6666)
    try:
        for _ in range(50):
            result = c.xreadgroup('testgroup', name, {'teststream': '>'}, count=1, block=2000)
    except redis.exceptions.ConnectionError as e:
        errors.append(f"{name}: {e}")
    except Exception as e:
        errors.append(f"{name}: {e}")

def producer():
    p = redis.Redis(port=6666)
    for i in range(200):
        p.xadd('teststream', {'key': f'value{i}'})
        time.sleep(0.005)

threads = []
for i in range(5):
    t = threading.Thread(target=consumer, args=(f'c{i}',))
    threads.append(t)
    t.start()

time.sleep(0.5)
pt = threading.Thread(target=producer)
pt.start()

pt.join()
for t in threads:
    t.join()

if errors:
    print(f"FAIL: {len(errors)} errors (double response causes protocol desync)")
    for e in errors[:5]:
        print(f"  {e}")
else:
    print("PASS: No protocol errors")
```

## Expected result (bug present)
Some consumers receive protocol errors or unexpected responses due to the double response from XREADGROUP.

## Oracle verdict

`./bench.sh reproduce kvrocks-3339-xreadgroup-double` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): during an 8 s run in which 16 consumers repeatedly issue `XREADGROUP ... COUNT 1 BLOCK 500` on an initially empty stream while a producer runs `XADD` about 50 times per second, some `XREADGROUP` reply is followed by extra bytes (a second RESP frame) within 150 ms, or a reply is malformed or of an unexpected type, a connection breaks, or an `XADD` fails. A worktree that does not build, or Kvrocks that exits during startup or does not listen on its port within 15 s, is also FAIL.
- **PASS** (exit 0): every `XREADGROUP` in the run produced exactly one RESP frame with no trailing bytes.
- **ERROR** (exit 2): `REBUILD.sh` or the built `build/kvrocks` binary is missing, `XGROUP CREATE` fails, or the run completes fewer than 10 `XREADGROUP` replies or 5 `XADD`s (the code path was not exercised).
