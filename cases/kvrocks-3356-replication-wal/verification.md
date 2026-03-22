# Verification: Kvrocks #3356

## Test procedure

```bash
#!/bin/bash
# Start master
./build/kvrocks -c master.conf &
MASTER_PID=$!
sleep 2

# Start replica
./build/kvrocks -c replica.conf &
REPLICA_PID=$!
sleep 3

# Record initial WAL size
INITIAL_SIZE=$(du -s /tmp/kvrocks-master/ | awk '{print $1}')

# Throttle replica (simulate slow consumer)
# Note: requires root on Linux
sudo tc qdisc add dev lo root netem delay 50ms rate 200kbit 2>/dev/null

# Generate sustained write load
redis-benchmark -p 6666 -t set -n 500000 -r 500000 -d 256 -c 50 -P 32 -q

sleep 10

# Check WAL size after load
FINAL_SIZE=$(du -s /tmp/kvrocks-master/ | awk '{print $1}')
GROWTH=$((FINAL_SIZE - INITIAL_SIZE))

# Cleanup
sudo tc qdisc del dev lo root 2>/dev/null
kill $MASTER_PID $REPLICA_PID 2>/dev/null
wait $MASTER_PID $REPLICA_PID 2>/dev/null

# WAL growth > 500MB indicates unbounded growth (bug present)
if [ "$GROWTH" -gt "512000" ]; then
    echo "FAIL: Bug is present — WAL grew by ${GROWTH}KB (unbounded)"
else
    echo "PASS: Bug is fixed — WAL growth bounded at ${GROWTH}KB"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** WAL grows unboundedly (hundreds of MB to GB) when replica is slow. Feed thread blocks indefinitely.
- **PASS (bug fixed):** WAL growth is bounded. Feed thread applies backpressure or timeout, preventing unbounded WAL accumulation. Slow replica may be disconnected or throttled instead of blocking the feed thread.
