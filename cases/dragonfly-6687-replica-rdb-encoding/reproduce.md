# Reproduce: Dragonfly #6687

## Prerequisites
A Dragonfly master with tiered storage and a replica (see setup.md).

## Step 1: Start master with tiered storage

```bash
./build-opt/dragonfly --port 6379 --logtostderr --proactor_threads 4 \
  --dbfilename="" --tiered_prefix=/tmp/dragonfly_tiered
```

## Step 2: Load data to trigger tiered storage

Load enough data so that some entries get offloaded to tiered storage:
```bash
# Load data that will be partially tiered
redis-benchmark -p 6379 -t set -n 500000 -r 500000 -d 512
```

Alternatively, load a Redis 6 RDB backup:
```bash
# If you have an RDB file:
./build-opt/dragonfly --port 6379 --logtostderr --proactor_threads 4 \
  --dbfilename=dump.rdb --tiered_prefix=/tmp/dragonfly_tiered
```

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
# Look for: "Unknown RDB string encoding 62"
```

## Expected result (bug present)
The replica logs show repeated errors:
```
Unknown RDB string encoding 62
```
The replica never completes sync and keeps retrying in a loop. `INFO replication` on the replica shows `master_link_status:down`.

```bash
redis-cli -p 6380 INFO replication | grep master_link_status
# master_link_status:down
```
