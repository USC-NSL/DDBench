# Reproduce: Dragonfly #6738

## Prerequisites
A running Dragonfly instance on the buggy version (see setup.md).

## Step 1: Start Dragonfly

```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 2 --dbfilename=""
```

## Step 2: Reproduce via pipeline flushing (recommended)

The most reliable reproduction sends non-blocking commands followed by a blocking command in a single pipeline. The replies for the non-blocking commands are held back until the blocking command completes or times out.

```bash
# Send SET + PING + BLPOP in a single pipeline
# The SET and PING replies should return immediately, but with the bug
# they are delayed until BLPOP times out (5 seconds)
START=$(date +%s)
printf "SET mykey myval\r\nPING\r\nBLPOP nolist 5\r\n" | redis-cli -p 6379 --pipe-timeout 10
END=$(date +%s)
ELAPSED=$((END - START))

if [ "$ELAPSED" -ge "4" ]; then
    echo "FAIL: Pipeline replies delayed ${ELAPSED}s by BLPOP"
else
    echo "PASS: Pipeline replies returned promptly"
fi
```

## Expected result (bug present)
The entire pipeline (including SET and PING replies) is delayed ~5 seconds until BLPOP times out. All replies are flushed together at the end.

## Expected result (bug fixed)
SET and PING replies are flushed immediately. Only the BLPOP response is delayed until its timeout.

## Alternative: EVAL/BRPOPLPUSH variant (less reliable)

**Note:** This variant may not reproduce on all buggy commits. The pipeline flushing variant above is more reliable.

In terminal 1:
```bash
redis-cli -p 6379 BRPOPLPUSH src dst 5
```

In terminal 2, within 5 seconds:
```bash
redis-cli -p 6379 EVAL "return redis.call('RPUSH', KEYS[1], ARGV[1])" 1 src hello
```

With the bug present, BRPOPLPUSH waits the full 5 seconds and returns `(nil)`, even though the RPUSH inside EVAL succeeded. When fixed, BRPOPLPUSH returns `"hello"` immediately.

Scripted version:
```bash
#!/bin/bash
redis-cli -p 6379 BRPOPLPUSH src dst 5 &
CONSUMER_PID=$!
sleep 1
redis-cli -p 6379 EVAL "return redis.call('RPUSH', KEYS[1], ARGV[1])" 1 src hello
START=$(date +%s)
wait $CONSUMER_PID
END=$(date +%s)
ELAPSED=$((END - START))

if [ "$ELAPSED" -ge "4" ]; then
    echo "FAIL: Consumer waited ${ELAPSED}s (full timeout)"
else
    echo "PASS: Consumer woke up after ${ELAPSED}s"
fi
```
