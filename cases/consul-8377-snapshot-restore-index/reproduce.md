# Reproduce: Consul #8377

## Prerequisites
- Consul binary built from the buggy commit
- `curl` and `jq` available

## Step 1: Start a 3-node Consul server cluster
```bash
# Start server 1 (bootstrap)
consul agent -server -bootstrap-expect=3 -data-dir=/tmp/consul1 \
  -bind=127.0.0.1 -client=127.0.0.1 \
  -http-port=8501 -server-port=8301 -serf-lan-port=8311 \
  -node=server1 -datacenter=dc1 &

# Start server 2
consul agent -server -data-dir=/tmp/consul2 \
  -bind=127.0.0.2 -client=127.0.0.2 \
  -http-port=8502 -server-port=8302 -serf-lan-port=8312 \
  -node=server2 -datacenter=dc1 -join=127.0.0.1:8311 &

# Start server 3
consul agent -server -data-dir=/tmp/consul3 \
  -bind=127.0.0.3 -client=127.0.0.3 \
  -http-port=8503 -server-port=8303 -serf-lan-port=8313 \
  -node=server3 -datacenter=dc1 -join=127.0.0.1:8311 &
```

## Step 2: Register an external node with a service and health check
```bash
curl -s -X PUT http://127.0.0.1:8501/v1/catalog/register -d '{
  "Node": "ext-node1",
  "Address": "10.0.0.1",
  "Service": {"Service": "web", "ID": "web-1", "Port": 80},
  "Check": {"CheckID": "web-check", "Name": "web health", "Status": "passing",
            "ServiceID": "web-1", "Node": "ext-node1"}
}'
```

## Step 3: Trigger snapshots on all servers at different raft indexes
```bash
# Write some data between snapshots to ensure different raft indexes
consul snapshot save -http-addr=http://127.0.0.1:8501 /tmp/snap1.snap
curl -s -X PUT http://127.0.0.1:8501/v1/kv/padding1 -d 'value1'
consul snapshot save -http-addr=http://127.0.0.2:8502 /tmp/snap2.snap
curl -s -X PUT http://127.0.0.1:8501/v1/kv/padding2 -d 'value2'
consul snapshot save -http-addr=http://127.0.0.3:8503 /tmp/snap3.snap
```

## Step 4: Stop all servers and restart (forcing snapshot restore)
```bash
# Kill all consul processes
pkill -9 consul
sleep 2

# Restart all servers (they restore from their individual snapshots)
# ... (same commands as Step 1)
```

## Step 5: Query health check with stale reads from each server
```bash
IDX1=$(curl -s 'http://127.0.0.1:8501/v1/health/checks/web?stale' | jq '.[0].CreateIndex')
IDX2=$(curl -s 'http://127.0.0.2:8502/v1/health/checks/web?stale' | jq '.[0].CreateIndex')
IDX3=$(curl -s 'http://127.0.0.3:8503/v1/health/checks/web?stale' | jq '.[0].CreateIndex')
echo "Server1: $IDX1, Server2: $IDX2, Server3: $IDX3"
```

## Expected result (bug present)
The three servers return different `CreateIndex` values for the same health check (e.g., `14`, `15`, `16`). Each server assigned its own snapshot restore index as the CreateIndex instead of preserving the original value.
