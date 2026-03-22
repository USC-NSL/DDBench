# Reproduce: ScyllaDB #25173

## Step 1: Start ScyllaDB
```bash
# Start a single node or multi-node cluster (see setup.md)
sleep 15  # Wait for node to fully initialize
```

## Step 2: Create schema
```bash
cqlsh 127.0.0.1 9042 <<EOF
CREATE KEYSPACE test_ks WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};
CREATE TABLE test_ks.data (id int PRIMARY KEY, val text);
EOF
```

## Step 3: Start concurrent writes in background
```bash
# Continuously write to the table
while true; do
  for i in $(seq 1 100); do
    cqlsh 127.0.0.1 9042 -e "INSERT INTO test_ks.data (id, val) VALUES ($RANDOM, 'value-$RANDOM');" 2>/dev/null &
  done
  wait
done &
WRITER_PID=$!
```

## Step 4: Drop the table while writes are active
```bash
sleep 5  # Let writes accumulate

# Drop the table — this triggers the truncate check
cqlsh 127.0.0.1 9042 -e "DROP TABLE test_ks.data;"
sleep 2

# Kill the writer
kill $WRITER_PID 2>/dev/null
wait $WRITER_PID 2>/dev/null
```

## Step 5: Verify raft applier is dead
```bash
# Try to create a new table — this requires the raft applier
timeout 30 cqlsh 127.0.0.1 9042 -e "CREATE TABLE test_ks.new_table (id int PRIMARY KEY, val text);"

if [ $? -ne 0 ]; then
  echo "BUG CONFIRMED: CREATE TABLE timed out — raft applier fiber is dead"
else
  echo "Raft applier is still working"
fi
```

## Expected result (bug present)
After the `DROP TABLE` executes with concurrent writes, subsequent schema operations (like `CREATE TABLE`) hang indefinitely because the raft applier fiber has exited.

## Notes
- The timing matters: writes must be actively in-flight when the DROP TABLE processes its truncate step.
- Multiple attempts may be needed to hit the exact race condition.
- Check logs for "Raft applier fiber exited" to confirm.
