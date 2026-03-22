# Reproduce: Dragonfly #6862

## Prerequisites
- Dragonfly built from source at a buggy commit (see setup.md)
- `redis-cli` and `redis-benchmark` available

## Step 1: Start Dragonfly in cluster mode with multiple threads

```bash
./build-dbg/dragonfly \
  --port 6380 \
  --logtostderr \
  --proactor_threads 4 \
  --dbfilename="" \
  --cluster_mode=yes \
  --cluster_node_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa &
DRAGONFLY_PID=$!
sleep 2
```

## Step 2: Configure initial cluster slots

Assign all slots to this node:
```bash
redis-cli -p 6380 DFLYCLUSTER CONFIG '
[
  {
    "slot_ranges": [{"start": 0, "end": 16383}],
    "master": {
      "id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "ip": "127.0.0.1",
      "port": 6380
    },
    "replicas": []
  }
]'
```

## Step 3: Start concurrent write load

```bash
redis-benchmark -p 6380 -t set -n 1000000 -c 50 -d 100 -r 100000 &
BENCH_PID=$!
```

## Step 4: Perform cluster management operations concurrently

While the write load is running, rapidly change cluster configuration:
```bash
for i in $(seq 1 100); do
    # Flush some slots and reconfigure
    redis-cli -p 6380 DFLYCLUSTER FLUSHSLOTS 100 101 102 103 2>/dev/null
    sleep 0.05

    # Reconfigure the cluster
    redis-cli -p 6380 DFLYCLUSTER CONFIG '
    [
      {
        "slot_ranges": [{"start": 0, "end": 16383}],
        "master": {
          "id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "ip": "127.0.0.1",
          "port": 6380
        },
        "replicas": []
      }
    ]' 2>/dev/null
    sleep 0.05
done
```

## Step 5: Check for crash

```bash
if kill -0 $DRAGONFLY_PID 2>/dev/null; then
    echo "Process is still running (bug may not have been triggered)"
else
    wait $DRAGONFLY_PID
    echo "CRASHED: exit code $?"
fi

kill $BENCH_PID 2>/dev/null
```

## Expected result (bug present)

Dragonfly crashes with an assertion failure in `db_slice.cc:550` or a segfault. The crash happens because concurrent access to `DbSlice` from write operations and cluster management operations is not properly synchronized.

## Expected result (bug absent)

Dragonfly continues running without crashing throughout the concurrent operations.

## Notes
- The crash is a race condition; it may take multiple attempts to trigger.
- Using Debug builds makes the crash more likely due to assertions being enabled.
- Increasing `--proactor_threads` and the benchmark concurrency (`-c`) increases the race window.
- The script in step 4 may need to run for longer on faster machines.
