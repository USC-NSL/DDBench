# Reproduce: ClickHouse #44865

## Prerequisites
- Two-replica ClickHouse cluster with ZooKeeper (see setup.md)
- `clickhouse-client` available

## Step 1: Create a replicated table

```sql
CREATE TABLE test_merges ON CLUSTER test_cluster
(
    id UInt64,
    ts DateTime DEFAULT now(),
    data String
)
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/test_merges', '{replica}')
ORDER BY id
SETTINGS
    parts_to_throw_insert = 300,
    max_parts_in_total = 500;
```

## Step 2: Generate sustained write load

Run a script that continuously inserts small batches to create many parts:
```bash
# Insert small batches rapidly to create many parts
for i in $(seq 1 500); do
    clickhouse-client -q "INSERT INTO test_merges (id, data) SELECT rand64(), randomString(100) FROM numbers(100)"
    sleep 0.1
done &
```

## Step 3: Monitor merge activity

```bash
# Watch merges on replica 1
watch -n 5 'clickhouse-client --port 9000 -q "
SELECT
    count() as active_parts,
    (SELECT count() FROM system.merges WHERE table = '\''test_merges'\'') as active_merges
FROM system.parts
WHERE active AND table = '\''test_merges'\''
"'
```

## Step 4: Observe stuck merges

Under sustained load, one replica's merge count will drop to 0 while the parts count continues to grow. This can take 30 minutes to several hours to manifest.

Key indicators:
```sql
-- No active merges despite many parts
SELECT count() FROM system.merges WHERE table = 'test_merges';
-- Returns: 0

-- Parts count growing
SELECT count() FROM system.parts WHERE active AND table = 'test_merges';
-- Returns: growing number (100, 200, 300...)

-- Eventually:
-- INSERT fails with: Too many parts (300). Merges are processing significantly slower than inserts.
```

## Expected result (bug present)

After sustained write load, one replica's background merges stop permanently. The parts count grows until inserts are rejected.

## Expected result (bug absent)

Merges continue to run on both replicas, keeping the parts count stable (typically under 50-100 parts).

## Notes
- This bug is a deadlock in `ReplicatedMergeTreeQueue` / `MergeTreeBackgroundExecutor` (root cause tracked in issue #43816).
- The timing is non-deterministic; it may require sustained load over 30+ minutes to trigger.
- Reducing `background_pool_size` to 1-2 threads increases the likelihood of hitting the deadlock.
