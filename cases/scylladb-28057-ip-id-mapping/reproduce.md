# Reproduce: ScyllaDB #28057

## Step 1: Start a 3-node cluster
```bash
# Start nodes 1, 2, 3 as described in setup.md
sleep 20  # Wait for cluster to fully form
```

## Step 2: Create schema and load data
```bash
cqlsh 127.0.0.1 9042 <<EOF
CREATE KEYSPACE test_ks WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 3};
CREATE TABLE test_ks.data (id int PRIMARY KEY, val text);
EOF

# Load data so streaming during replace is non-trivial
for i in $(seq 1 5000); do
  cqlsh 127.0.0.1 9042 -e "INSERT INTO test_ks.data (id, val) VALUES ($i, '$(head -c 512 /dev/urandom | base64)');" &
  [ $(( i % 50 )) -eq 0 ] && wait
done
wait
```

## Step 3: Kill node 3 (the node to be replaced)
```bash
# Kill node 3
nodetool -h 127.0.0.3 assassinate 2>/dev/null || kill -9 $(pgrep -f "scylla-replace-node3") 2>/dev/null
sleep 5
```

## Step 4: Start a replacement node and kill it during streaming
```bash
# Start node 4 as a replacement for node 3
./build/dev/scylla --workdir /tmp/scylla-replace-node4 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.4 --api-port 10000 \
  --rpc-address 127.0.0.4 --listen-address 127.0.0.4 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 \
  --replace-address-first-boot 127.0.0.3 &
NODE4_PID=$!

# Wait for streaming to start (watch logs for "streaming" messages)
sleep 15

# Kill node 4 during streaming to simulate a failed replace
kill -9 $NODE4_PID
sleep 2
```

## Step 5: Shut down all remaining nodes before rollback
```bash
# Kill nodes 1 and 2 immediately (before the replace can roll back)
kill -9 $(pgrep -f "scylla-replace-node1") 2>/dev/null
kill -9 $(pgrep -f "scylla-replace-node2") 2>/dev/null
sleep 5
```

## Step 6: Restart nodes 1 and 2
```bash
# Restart node 1
./build/dev/scylla --workdir /tmp/scylla-replace-node1 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.1 --api-port 10000 \
  --rpc-address 127.0.0.1 --listen-address 127.0.0.1 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &

# Restart node 2
./build/dev/scylla --workdir /tmp/scylla-replace-node2 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.2 --api-port 10000 \
  --rpc-address 127.0.0.2 --listen-address 127.0.0.2 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &

sleep 20
```

## Step 7: Check for errors
```bash
nodetool -h 127.0.0.1 status
# Expected: errors related to IP/ID mapping for the replacing node
```

## Expected result (bug present)
`nodetool status` reports errors or shows incorrect node information. The cluster may have difficulty identifying the state of the node being replaced, because the IP-to-ID mapping for the replacing node was not preserved across the restart.
