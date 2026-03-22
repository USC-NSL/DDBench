# Verification: Dragonfly #6822

## Automated test

```bash
#!/bin/bash
# Start Dragonfly
./build-opt/dragonfly --port 6379 --logtostderr --proactor_threads 4 --dbfilename="" &
PID=$!
sleep 2

# Load 600k keys with 8-second TTL
redis-benchmark -p 6379 -t set -n 600000 -r 600000 -d 100 \
  -- SET __rand_field__ __rand_value__ EX 8 >/dev/null 2>&1

echo "Waiting for keys to start expiring..."
sleep 9

# Test responsiveness during expiry
FAIL=0
for i in $(seq 1 10); do
    RESULT=$(timeout 3 redis-cli -p 6379 PING 2>/dev/null)
    if [ "$RESULT" != "PONG" ]; then
        FAIL=$((FAIL + 1))
    fi
    sleep 0.3
done

kill $PID 2>/dev/null
wait $PID 2>/dev/null

if [ "$FAIL" -gt "2" ]; then
    echo "FAIL: Bug is present — $FAIL/10 PINGs timed out during expiry"
else
    echo "PASS: Bug is fixed — server remained responsive during expiry"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** Multiple PING commands time out or take >3 seconds during the key expiry cycle. CPU is at 100%.
- **PASS (bug fixed):** PING commands return PONG within a few milliseconds even during mass key expiry. Server remains responsive.
