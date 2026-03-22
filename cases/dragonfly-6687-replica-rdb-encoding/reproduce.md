# Reproduce: Dragonfly #6687

## Prerequisites
A Dragonfly master with tiered storage and a replica (see setup.md).

## Step 1: Start master with tiered storage

```bash
./build-opt/dragonfly --port 6379 --logtostderr --proactor_threads 4 \
  --dbfilename="" \
  --tiered_prefix=/tmp/dragonfly_tiered \
  --tiered_offload_threshold=1.0 \
  --serialization_max_chunk_size=64000 \
  --maxmemory=512mb
```

## Step 2: Load data to trigger tiered storage

Load data with specific patterns that expose the tiered serialization race. Both large strings and hash structures are needed to reliably trigger the bug:

```bash
# Large string values (3KB each) — these get offloaded to tiered storage
redis-cli -p 6379 DEBUG POPULATE 200000 key 3000

# Hash values with many elements — these create complex RDB serialization patterns
redis-cli -p 6379 DEBUG POPULATE 200 hash 70 RAND TYPE HASH ELEMENTS 900
```

**Note:** Simple `redis-benchmark -t set -d 512` is often insufficient to trigger the bug. The combination of large strings + hash structures with `--serialization_max_chunk_size=64000` and `--tiered_offload_threshold=1.0` is required for reliable reproduction. The bug involves tiered entries being serialized at unsafe times, interleaving with snapshot generation and corrupting the RDB stream.

## Step 3: Start replica and initiate sync

```bash
./build-opt/dragonfly --port 6380 --logtostderr --proactor_threads 4 --dbfilename=""
```

```bash
redis-cli -p 6380 REPLICAOF localhost 6379
```

## Step 4: Observe replica logs

```bash
# Watch replica logs for the error
# Look for: "Unknown RDB string encoding" (encoding number may vary: 10, 62, etc.)
```

## Expected result (bug present)
The replica logs show repeated errors:
```
Unknown RDB string encoding 10
```
The replica never completes sync and keeps retrying in a loop. `INFO replication` on the replica shows `master_link_status:down`.

```bash
redis-cli -p 6380 INFO replication | grep master_link_status
# master_link_status:down
```
