# Reproduce: etcd #20269

## Step 1: Start a 2-node cluster
```bash
rm -rf /tmp/etcd-rejoin-node{1,2,3}

# Start node1 and node2 as described in setup.md
# Wait for cluster to be healthy
sleep 5
bin/etcdctl --endpoints=http://127.0.0.1:2379 endpoint health
```

## Step 2: Add a learner (node3)
```bash
bin/etcdctl --endpoints=http://127.0.0.1:2379 member add node3 \
  --peer-urls=http://127.0.0.1:2384 --learner

# Start node3 as learner
bin/etcd --name node3 \
  --data-dir /tmp/etcd-rejoin-node3 \
  --listen-peer-urls http://127.0.0.1:2384 \
  --listen-client-urls http://127.0.0.1:2383 \
  --initial-advertise-peer-urls http://127.0.0.1:2384 \
  --advertise-client-urls http://127.0.0.1:2383 \
  --initial-cluster "node1=http://127.0.0.1:2380,node2=http://127.0.0.1:2382,node3=http://127.0.0.1:2384" \
  --initial-cluster-state existing &
NODE3_PID=$!
sleep 3
```

## Step 3: Write some data to advance the raft log
```bash
for i in $(seq 1 100); do
  bin/etcdctl --endpoints=http://127.0.0.1:2379 put key-$i value-$i
done
```

## Step 4: Simulate failure — kill and remove node3
```bash
kill $NODE3_PID
sleep 2

# Get node3's member ID
MEMBER_ID=$(bin/etcdctl --endpoints=http://127.0.0.1:2379 member list --write-out=json | python3 -c "
import sys, json
members = json.load(sys.stdin)['members']
for m in members:
    if m['name'] == 'node3':
        print(format(m['ID'], 'x'))
")

# Remove node3
bin/etcdctl --endpoints=http://127.0.0.1:2379 member remove $MEMBER_ID
```

## Step 5: Reset node3's data and re-add
```bash
# Wipe node3's data directory (simulating a reset)
rm -rf /tmp/etcd-rejoin-node3

# Re-add node3 as a learner
bin/etcdctl --endpoints=http://127.0.0.1:2379 member add node3 \
  --peer-urls=http://127.0.0.1:2384 --learner

# Restart node3 with clean state
bin/etcd --name node3 \
  --data-dir /tmp/etcd-rejoin-node3 \
  --listen-peer-urls http://127.0.0.1:2384 \
  --listen-client-urls http://127.0.0.1:2383 \
  --initial-advertise-peer-urls http://127.0.0.1:2384 \
  --advertise-client-urls http://127.0.0.1:2383 \
  --initial-cluster "node1=http://127.0.0.1:2380,node2=http://127.0.0.1:2382,node3=http://127.0.0.1:2384" \
  --initial-cluster-state existing &
NODE3_PID=$!
sleep 5
```

## Expected result (bug present)
Node3 panics shortly after starting with:
```
panic: tocommit(X) is out of range [lastIndex(0)]. Was the raft log corrupted, truncated, or lost?
```
The process exits immediately.
