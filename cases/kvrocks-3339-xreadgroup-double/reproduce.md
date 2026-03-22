# Reproduce: Kvrocks #3339

## Prerequisites
A running Kvrocks instance (see setup.md).

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
