# Verification: NATS #7852

## Test procedure
Run both consumer benchmarks from reproduce.md and compare delivery rates.

```bash
rm -rf /tmp/nats-bench-data
./nats-server -c /tmp/nats-bench.conf &
SERVER_PID=$!
sleep 2

# Create stream and publish messages
nats stream add BENCH --subjects="bench.>" --storage=memory --replicas=1 --retention=limits --max-msgs=-1 --max-bytes=-1 --discard=old --server=nats://127.0.0.1:4222
nats bench bench.test --pub --msgs=500000 --size=128 --server=nats://127.0.0.1:4222

# Create both consumers
nats consumer add BENCH nofilter --pull --ack=none --replay=instant --deliver=all --server=nats://127.0.0.1:4222
nats consumer add BENCH filtered --pull --ack=none --replay=instant --deliver=all --filter-subject="bench.>" --server=nats://127.0.0.1:4222

# Measure baseline (no filter)
START=$(date +%s%N)
nats consumer next BENCH nofilter --count=500000 --server=nats://127.0.0.1:4222 > /dev/null 2>&1
END=$(date +%s%N)
BASELINE_MS=$(( (END - START) / 1000000 ))

# Measure filtered
START=$(date +%s%N)
nats consumer next BENCH filtered --count=500000 --server=nats://127.0.0.1:4222 > /dev/null 2>&1
END=$(date +%s%N)
FILTERED_MS=$(( (END - START) / 1000000 ))

echo "Baseline (no filter): ${BASELINE_MS}ms"
echo "Filtered (match all): ${FILTERED_MS}ms"

# Calculate percentage difference
if [ "$BASELINE_MS" -gt 0 ]; then
  DIFF=$(( (FILTERED_MS - BASELINE_MS) * 100 / BASELINE_MS ))
  echo "Performance difference: ${DIFF}%"
  if [ "$DIFF" -gt 15 ]; then
    echo "FAIL: Filtered consumer is ${DIFF}% slower — bug is present"
  else
    echo "PASS: Performance difference is within acceptable range — bug is fixed"
  fi
fi

kill $SERVER_PID 2>/dev/null
```

- **FAIL:** Filtered consumer (matching all subjects) is >15% slower than no-filter consumer.
- **PASS:** Both consumers deliver at comparable rates (within 15% of each other).
