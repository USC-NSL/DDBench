# Verification: Kvrocks #3339

## Automated test

Run the Python script from reproduce.md, or use this bash-based check:

```bash
#!/bin/bash
./build/kvrocks --port 6666 --dir /tmp/kvrocks-data --log-dir /tmp/kvrocks-logs &
PID=$!
sleep 2

# Setup
redis-cli -p 6666 DEL teststream 2>/dev/null
redis-cli -p 6666 XADD teststream '*' init init
redis-cli -p 6666 XGROUP CREATE teststream testgroup 0

# Start 5 blocking consumers in background
for i in $(seq 1 5); do
    (for j in $(seq 1 20); do
        redis-cli -p 6666 XREADGROUP GROUP testgroup "consumer$i" BLOCK 1000 COUNT 1 STREAMS teststream '>' 2>&1
    done) > /tmp/consumer_$i.out 2>&1 &
done

sleep 0.5

# Producer: rapid XADD
for i in $(seq 1 100); do
    redis-cli -p 6666 XADD teststream '*' key "value$i" >/dev/null 2>&1
done

# Wait for consumers to finish
sleep 5
wait

# Check for protocol errors in output
ERROR_COUNT=0
for i in $(seq 1 5); do
    if grep -qi "error\|ERR\|WRONGTYPE\|invalid" /tmp/consumer_$i.out 2>/dev/null; then
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
done

kill $PID 2>/dev/null
wait $PID 2>/dev/null

if [ "$ERROR_COUNT" -gt "0" ]; then
    echo "FAIL: Bug is present — $ERROR_COUNT consumers got protocol errors (double response)"
else
    echo "PASS: Bug is fixed — all consumers received valid responses"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** Consumers receive protocol errors, connection errors, or unexpected response types due to double responses from XREADGROUP BLOCK.
- **PASS (bug fixed):** All consumers receive exactly one response per XREADGROUP command with no protocol errors.
