# Reproduce: ClickHouse #43816

## Prerequisites
A 2-replica ReplicatedMergeTree cluster with ZooKeeper (see setup.md). Use ClickHouse version 22.10 or earlier.

## Step 1: Create a ReplicatedMergeTree table

On both replicas:
```sql
CREATE TABLE test_replicated (
    event_date Date,
    key UInt64,
    value String
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/test_replicated', '{replica}')
PARTITION BY toYYYYMM(event_date)
ORDER BY key;
```

## Step 2: Generate sustained write load

Run concurrent inserts from multiple clients to create many small parts:
```bash
for i in $(seq 1 20); do
    clickhouse-client --port 9001 -q "
        INSERT INTO test_replicated
        SELECT today(), rand64(), randomString(100)
        FROM numbers(10000)
    " &
done
wait
```

Repeat this in a loop to keep creating parts:
```bash
while true; do
    for i in $(seq 1 10); do
        clickhouse-client --port 9001 -q "
            INSERT INTO test_replicated
            SELECT today(), rand64(), randomString(100)
            FROM numbers(5000)
        " &
    done
    wait
    sleep 1
done
```

## Step 3: Monitor for deadlock

```bash
# Check merge progress
watch -n 5 'clickhouse-client --port 9001 -q "
    SELECT elapsed, progress, num_parts, result_part_name
    FROM system.merges FORMAT PrettyCompact"'

# Check thread stacks for deadlock
clickhouse-client --port 9001 -q "
    SELECT count(), arrayStringConcat(arrayMap(x -> demangle(addressToSymbol(x)), trace), '\n') AS stack
    FROM system.stack_trace
    WHERE stack LIKE '%setActualPartName%' OR stack LIKE '%pthread_cond_wait%'
    GROUP BY stack
    FORMAT Vertical"
```

## Expected result (bug present)
After several minutes of sustained writes, merges show `progress = 0` and remain stuck. Thread stacks show threads waiting inside `ReplicatedMergeTreeQueue` and `MergeTreeBackgroundExecutor` in a deadlock pattern.
