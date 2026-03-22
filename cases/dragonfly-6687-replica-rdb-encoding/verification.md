# Verification: Dragonfly #6687

## Automated test

```bash
#!/bin/bash
# Start master with tiered storage
./build-opt/dragonfly --port 6379 --logtostderr --proactor_threads 4 \
  --dbfilename="" --tiered_prefix=/tmp/dragonfly_tiered &
MASTER_PID=$!
sleep 2

# Load data
redis-benchmark -p 6379 -t set -n 500000 -r 500000 -d 512 -q

# Start replica
./build-opt/dragonfly --port 6380 --logtostderr --proactor_threads 4 --dbfilename="" &
REPLICA_PID=$!
sleep 2

# Initiate replication
redis-cli -p 6380 REPLICAOF localhost 6379

# Wait for sync to complete (or fail)
sleep 15

# Check replication status
LINK_STATUS=$(redis-cli -p 6380 INFO replication 2>/dev/null | grep master_link_status | tr -d '\r')

kill $MASTER_PID $REPLICA_PID 2>/dev/null
wait $MASTER_PID $REPLICA_PID 2>/dev/null

if echo "$LINK_STATUS" | grep -q "up"; then
    echo "PASS: Bug is fixed — replica synced successfully"
else
    echo "FAIL: Bug is present — replica sync failed ($LINK_STATUS)"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** `master_link_status:down` and replica logs contain "Unknown RDB string encoding 62".
- **PASS (bug fixed):** `master_link_status:up` and replica has synced data from master.
