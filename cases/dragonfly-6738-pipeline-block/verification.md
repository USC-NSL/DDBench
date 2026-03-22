# Verification: Dragonfly #6738

## Automated test

```bash
#!/bin/bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 2 --dbfilename="" &
PID=$!
sleep 2

# Clean up any leftover keys
redis-cli -p 6379 DEL src dst >/dev/null 2>&1

# Start blocking consumer in background
redis-cli -p 6379 BRPOPLPUSH src dst 5 &
CONSUMER_PID=$!
sleep 1

# Push via Lua EVAL
redis-cli -p 6379 EVAL "return redis.call('RPUSH', KEYS[1], ARGV[1])" 1 src hello

START=$(date +%s)
wait $CONSUMER_PID
END=$(date +%s)
ELAPSED=$((END - START))

kill $PID 2>/dev/null
wait $PID 2>/dev/null

if [ "$ELAPSED" -ge "4" ]; then
    echo "FAIL: Bug is present — consumer waited ${ELAPSED}s (full timeout, not woken by EVAL RPUSH)"
else
    echo "PASS: Bug is fixed — consumer woke up after ${ELAPSED}s"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** The BRPOPLPUSH consumer waits the full timeout (5 seconds) and returns nil.
- **PASS (bug fixed):** The BRPOPLPUSH consumer returns the pushed value within 1-2 seconds.
