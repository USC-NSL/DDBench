# Reproduce: Redpanda #16944

## Step 1: Start Redpanda
```bash
rm -rf /tmp/redpanda-data
./build/release/bin/redpanda \
  --redpanda-cfg /tmp/redpanda.yaml \
  --smp 4 \
  --memory 4G &
RPANDA_PID=$!
sleep 5
```

## Step 2: Create a topic with multiple partitions
```bash
# Using rpk or kafka tools
rpk topic create high-throughput -p 16 --brokers localhost:9092

# Or using kafka-topics
kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic high-throughput --partitions 16
```

## Step 3: Generate high write throughput
```bash
# Option A: Using kafka-producer-perf-test
kafka-producer-perf-test \
  --topic high-throughput \
  --num-records 10000000 \
  --record-size 1024 \
  --throughput -1 \
  --producer-props bootstrap.servers=localhost:9092 \
    acks=all \
    batch.size=65536 \
    linger.ms=5

# Option B: Using rpk
for i in $(seq 1 1000000); do
  echo "payload-$i-$(head -c 1024 /dev/urandom | base64)" | rpk topic produce high-throughput --brokers localhost:9092 &
  # Limit concurrency
  [ $(( i % 100 )) -eq 0 ] && wait
done

# Option C: Multiple concurrent producers
for producer in $(seq 1 10); do
  kafka-producer-perf-test \
    --topic high-throughput \
    --num-records 1000000 \
    --record-size 1024 \
    --throughput -1 \
    --producer-props bootstrap.servers=localhost:9092 acks=all &
done
wait
```

## Step 4: Check for oversized allocation warnings
```bash
# Check Redpanda logs for the warning
grep "oversized allocation" /tmp/redpanda-data/redpanda.log 2>/dev/null
# Or check stderr output
# The warning includes "raft::replicate_batcher::flush" in the stack trace
```

## Expected result (bug present)
The Redpanda log contains multiple entries like:
```
WARNING: oversized allocation: 262144 bytes, please report: raft::replicate_batcher::flush
```

These appear during the sustained high-throughput write period.
