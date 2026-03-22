# Reproduce: etcd #20793

## Step 1: Start 3-node cluster on etcd 3.5.19
```bash
rm -rf /tmp/etcd-upgrade-node{1,2,3}

# Start all 3 nodes using etcd 3.5.19 binaries (see setup.md)
sleep 5
```

## Step 2: Add a learner and promote it
```bash
ETCDCTL=/tmp/etcd-v3.5.19-linux-amd64/etcdctl

# Add node as learner first, then promote
# (Or simply have a member that was added as learner and promoted in the cluster history)
# The key is that a learner promotion event exists in the cluster's history

# Write some data
for i in $(seq 1 50); do
  $ETCDCTL --endpoints=http://127.0.0.1:2379 put key-$i val-$i
done
```

## Step 3: Rolling upgrade to 3.5.21
```bash
# Stop each node one at a time and restart with 3.5.21 binary
for node_num in 1 2 3; do
  # Stop the node (find its PID)
  # Restart with 3.5.21 binary using same data-dir and flags
  # Wait for cluster health before proceeding to next node
  sleep 5
done

# Verify cluster health
/tmp/etcd-v3.5.21-linux-amd64/etcdctl --endpoints=http://127.0.0.1:2379 endpoint health
```

## Step 4: Rolling upgrade to 3.6.4
```bash
# Stop each node one at a time and restart with 3.6.4 binary
for node_num in 1 2 3; do
  # Stop the node
  # Restart with 3.6.4 binary using same data-dir and flags
  # On the final node upgrade, the error appears
  sleep 5
done
```

## Expected result (bug present)
The final upgrade step to 3.6.4 fails with:
```
too many learner members in cluster
```

The node refuses to start because the v3store still has the promoted member marked as a learner. The cluster cannot complete the upgrade to 3.6.x.

## Notes
- The etcd project provides an `upgradeDemo` tool that automates this multi-version upgrade scenario.
- The bug specifically affects clusters where a learner was promoted during the 3.5.x lifecycle.
