# Reproduce: NATS #7852

## Step 1: Start NATS server with JetStream
```bash
rm -rf /tmp/nats-bench-data
./nats-server -c /tmp/nats-bench.conf &
sleep 2
```

## Step 2: Create a stream
```bash
nats stream add BENCH \
  --subjects="bench.>" \
  --storage=memory \
  --replicas=1 \
  --retention=limits \
  --max-msgs=-1 \
  --max-bytes=-1 \
  --discard=old \
  --server=nats://127.0.0.1:4222
```

## Step 3: Publish test messages
```bash
# Publish a large number of messages
nats bench bench.test --pub --msgs=1000000 --size=128 --server=nats://127.0.0.1:4222
```

## Step 4: Benchmark consumer WITHOUT filter (baseline)
```bash
# Create consumer with no filter
nats consumer add BENCH consumer-nofilter \
  --pull \
  --ack=none \
  --replay=instant \
  --deliver=all \
  --server=nats://127.0.0.1:4222

# Benchmark delivery rate
time nats consumer next BENCH consumer-nofilter --count=1000000 --server=nats://127.0.0.1:4222 > /dev/null
echo "Baseline (no filter) complete"
```

## Step 5: Benchmark consumer WITH FilterSubjects matching all
```bash
# Create consumer with FilterSubjects that matches all subjects
nats consumer add BENCH consumer-filtered \
  --pull \
  --ack=none \
  --replay=instant \
  --deliver=all \
  --filter-subject="bench.>" \
  --server=nats://127.0.0.1:4222

# Benchmark delivery rate
time nats consumer next BENCH consumer-filtered --count=1000000 --server=nats://127.0.0.1:4222 > /dev/null
echo "Filtered (matching all) complete"
```

## Step 6: Compare results
The filtered consumer should be >20% slower than the no-filter consumer, even though both deliver exactly the same messages.

## Alternative: Go benchmark
```go
// Write a Go benchmark that creates both consumer types and measures
// delivery throughput using the nats.go client library.
// Compare msgs/sec for:
//   1. Consumer with no filter
//   2. Consumer with FilterSubjects=["bench.>"]
```

## Expected result (bug present)
The consumer with `FilterSubjects` matching all subjects delivers messages at least 20% slower than the consumer with no filter configured.
