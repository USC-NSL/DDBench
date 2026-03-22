# Reproduce: ScyllaDB #27956

## Step 1: Start ScyllaDB
```bash
rm -rf /tmp/scylla-staging
./build/dev/scylla --workdir /tmp/scylla-staging \
  --smp 2 --memory 2G \
  --api-address 127.0.0.1 --api-port 10000 \
  --rpc-address 127.0.0.1 --listen-address 127.0.0.1 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &
SCYLLA_PID=$!
sleep 15
```

## Step 2: Create schema with a materialized view
```bash
cqlsh 127.0.0.1 9042 <<EOF
CREATE KEYSPACE test_ks WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

CREATE TABLE test_ks.base_table (
  id int PRIMARY KEY,
  category text,
  value text
);

CREATE MATERIALIZED VIEW test_ks.by_category AS
  SELECT * FROM test_ks.base_table
  WHERE category IS NOT NULL AND id IS NOT NULL
  PRIMARY KEY (category, id);
EOF
```

## Step 3: Insert data and force view update failure
```bash
# Insert data
for i in $(seq 1 1000); do
  cqlsh 127.0.0.1 9042 -e "INSERT INTO test_ks.base_table (id, category, value) VALUES ($i, 'cat-$(( i % 10 ))', 'val-$i');"
done

# Verify view is consistent
BASE_COUNT=$(cqlsh 127.0.0.1 9042 -e "SELECT count(*) FROM test_ks.base_table;" | grep -oP '\d+' | head -1)
VIEW_COUNT=$(cqlsh 127.0.0.1 9042 -e "SELECT count(*) FROM test_ks.by_category;" | grep -oP '\d+' | head -1)
echo "Before restart: base=$BASE_COUNT, view=$VIEW_COUNT"
```

## Step 4: Force staging SSTables and restart
```bash
# Insert more data
for i in $(seq 1001 2000); do
  cqlsh 127.0.0.1 9042 -e "INSERT INTO test_ks.base_table (id, category, value) VALUES ($i, 'cat-$(( i % 10 ))', 'val-$i');"
done

# Force a flush to create SSTables
nodetool -h 127.0.0.1 flush

# Kill the node abruptly while view updates may still be pending
# (This simulates a crash that leaves staging SSTables)
kill -9 $SCYLLA_PID
sleep 5
```

## Step 5: Restart the node
```bash
./build/dev/scylla --workdir /tmp/scylla-staging \
  --smp 2 --memory 2G \
  --api-address 127.0.0.1 --api-port 10000 \
  --rpc-address 127.0.0.1 --listen-address 127.0.0.1 \
  --seed-provider-parameters seeds=127.0.0.1 \
  --native-transport-port 9042 &
SCYLLA_PID=$!
sleep 20  # Wait for full startup
```

## Step 6: Check for inconsistency
```bash
BASE_COUNT=$(cqlsh 127.0.0.1 9042 -e "SELECT count(*) FROM test_ks.base_table;" | grep -oP '\d+' | head -1)
VIEW_COUNT=$(cqlsh 127.0.0.1 9042 -e "SELECT count(*) FROM test_ks.by_category;" | grep -oP '\d+' | head -1)
echo "After restart: base=$BASE_COUNT, view=$VIEW_COUNT"

if [ "$BASE_COUNT" != "$VIEW_COUNT" ]; then
  echo "BUG CONFIRMED: Base table has $BASE_COUNT rows but view has $VIEW_COUNT rows"
else
  echo "View is consistent"
fi
```

## Expected result (bug present)
After restart, the materialized view has fewer rows than the base table. The staging SSTables that needed view update processing were not discovered by the view update generator.
