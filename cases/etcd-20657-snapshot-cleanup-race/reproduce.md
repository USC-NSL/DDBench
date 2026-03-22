# Reproduce: etcd #20657

## Step 1: Start a 3-node cluster with low snapshot count
```bash
# Clean up any previous data
rm -rf /tmp/etcd-node{1,2,3}

# Start all 3 nodes as described in setup.md with --snapshot-count=2
# (See setup.md for full commands)
```

## Step 2: Generate rapid writes to force frequent snapshots
```bash
# In a loop, write keys rapidly to force snapshot creation
for i in $(seq 1 10000); do
  bin/etcdctl --endpoints=http://127.0.0.1:2379 put key-$i value-$i &
done
wait
```

## Step 3: Force leader changes during writes
While writes are ongoing, trigger leader changes to create conditions where followers need to apply snapshots:
```bash
# In a separate terminal, repeatedly move the leader
for i in $(seq 1 20); do
  LEADER_ID=$(bin/etcdctl --endpoints=http://127.0.0.1:2379,http://127.0.0.1:2381,http://127.0.0.1:2383 endpoint status --write-out=json | python3 -c "import sys,json; eps=json.load(sys.stdin); print([e['Status']['leader'] for e in eps][0])")
  bin/etcdctl --endpoints=http://127.0.0.1:2379 move-leader $LEADER_ID 2>/dev/null || true
  sleep 0.2
done
```

## Step 4: Observe the crash
```bash
# Watch the logs of the follower nodes for panic
# One of the followers should panic with:
#   "open ...snap.db: no such file or directory"

# You can also check process status
for port in 2379 2381 2383; do
  bin/etcdctl --endpoints=http://127.0.0.1:$port endpoint health 2>&1 || echo "Node on port $port is DOWN"
done
```

## Expected result (bug present)
One of the follower nodes panics with a "file not found" error referencing a `.snap.db` file. The node process exits.

## Notes
- The low `--snapshot-count=2` is critical to reproduce — it forces very frequent snapshot creation.
- The race is timing-dependent, so multiple attempts may be needed.
- Running with Go's race detector (`-race` flag in build) can also help surface the race.
