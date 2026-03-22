# Reproduce: Dragonfly #6822

## Prerequisites
A running Dragonfly instance on the buggy version (see setup.md).

## Step 1: Start Dragonfly

```bash
./build-opt/dragonfly --port 6379 --logtostderr --proactor_threads 4 --dbfilename=""
```

## Step 2: Load keys with TTL

Use redis-benchmark or a script to load 500,000+ keys all with the same short TTL:

```bash
# Load 600k keys with 10-second TTL
redis-benchmark -p 6379 -t set -n 600000 -r 600000 -d 100 \
  -- SET __rand_field__ __rand_value__ EX 10
```

Or with a Python script:
```python
import redis
import time

r = redis.Redis(port=6379)
pipe = r.pipeline()
for i in range(600000):
    pipe.setex(f"key:{i}", 10, f"value:{i}")
    if i % 10000 == 0:
        pipe.execute()
        pipe = r.pipeline()
pipe.execute()
print(f"Loaded 600k keys, waiting for expiry...")
```

## Step 3: Wait for expiry and test responsiveness

```bash
# Wait for keys to expire, then continuously PING
sleep 10

# In a loop, measure PING latency
for i in $(seq 1 20); do
    START=$(date +%s%N)
    timeout 5 redis-cli -p 6379 PING
    END=$(date +%s%N)
    ELAPSED=$(( (END - START) / 1000000 ))
    echo "PING $i: ${ELAPSED}ms"
    sleep 0.5
done
```

## Expected result (bug present)
During the expiry cycle, PING commands either time out (5s+) or show extremely high latency (>1000ms). CPU usage on the Dragonfly process goes to 100%.
