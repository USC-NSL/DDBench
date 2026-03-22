# Reproduce: Dragonfly #6738

## Prerequisites
A running Dragonfly instance on the buggy version (see setup.md).

## Step 1: Start Dragonfly

```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 2 --dbfilename=""
```

## Step 2: Start a blocking consumer

In terminal 1:
```bash
redis-cli -p 6379 BRPOPLPUSH src dst 5
```

This will block waiting for an element on the `src` list, with a 5-second timeout.

## Step 3: Push via Lua EVAL

In terminal 2, within 5 seconds:
```bash
redis-cli -p 6379 EVAL "return redis.call('RPUSH', KEYS[1], ARGV[1])" 1 src hello
```

## Step 4: Observe the result

Watch terminal 1.

## Expected result (bug present)
The `BRPOPLPUSH` in terminal 1 waits the full 5 seconds and returns `(nil)`, even though the RPUSH inside EVAL succeeded (returned 1). The element `hello` is left in `src` unconsumed.

## Expected result (bug fixed)
The `BRPOPLPUSH` in terminal 1 returns `"hello"` immediately after the EVAL runs, and the element is moved to `dst`.

## Scripted reproduction (EVAL variant)

```bash
#!/bin/bash
# Start consumer in background
redis-cli -p 6379 BRPOPLPUSH src dst 5 &
CONSUMER_PID=$!
sleep 1

# Push via EVAL
redis-cli -p 6379 EVAL "return redis.call('RPUSH', KEYS[1], ARGV[1])" 1 src hello

# Measure how long consumer takes
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

## Alternative: Pipeline flushing variant

The bug also manifests as a pipeline flushing issue: when a blocking command (e.g., `BLPOP`) is in a pipeline, replies for *preceding* non-blocking commands (e.g., `SET`, `PING`) are held back until the blocking command completes or times out.

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
