# Reproduce: ScyllaDB #28200

## Step 1: Build with ASAN
```bash
cd scylladb
./configure.py --mode=dev --enable-asan
ninja build/dev/scylla
```

## Step 2: Start a 2-node cluster
```bash
# Start node 1
./build/dev/scylla --workdir /tmp/scylla-uaf-node1 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.1 --api-port 10000 \
  --rpc-address 127.0.0.1 --listen-address 127.0.0.1 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &
NODE1_PID=$!
sleep 10

# Start node 2
./build/dev/scylla --workdir /tmp/scylla-uaf-node2 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.2 --api-port 10000 \
  --rpc-address 127.0.0.2 --listen-address 127.0.0.2 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9043 &
NODE2_PID=$!
sleep 15
```

## Step 3: Create schema and load data
```bash
cqlsh 127.0.0.1 9042 <<EOF
CREATE KEYSPACE test_ks WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 2};
CREATE TABLE test_ks.data (id int PRIMARY KEY, val text);
EOF

# Insert enough data to require meaningful streaming
for i in $(seq 1 10000); do
  cqlsh 127.0.0.1 9042 -e "INSERT INTO test_ks.data (id, val) VALUES ($i, '$(head -c 1024 /dev/urandom | base64)');"
done
```

## Step 4: Trigger topology change with streaming
```bash
# Option A: Add a third node (triggers streaming)
./build/dev/scylla --workdir /tmp/scylla-uaf-node3 \
  --smp 2 --memory 2G \
  --api-address 127.0.0.3 --api-port 10000 \
  --rpc-address 127.0.0.3 --listen-address 127.0.0.3 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9044 &

# Option B: Decommission node 2 (triggers streaming)
nodetool -h 127.0.0.2 decommission

# Option C: Rebuild node 2
nodetool -h 127.0.0.2 rebuild
```

## Step 5: Watch for ASAN report
```bash
# Monitor the logs of all nodes for ASAN errors
# The UAF typically occurs during the streaming phase
# Check stderr output or log files for "AddressSanitizer: heap-use-after-free"
```

## Expected result (bug present)
One of the nodes (typically the one performing the streaming) crashes with an ASAN use-after-free report pointing to `streaming_task_impl::run` and `coroutine::lambda`.
