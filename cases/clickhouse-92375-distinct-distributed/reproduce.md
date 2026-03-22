# Reproduce: ClickHouse #92375

## Prerequisites
A running ClickHouse cluster with at least two shards (see setup.md).

## Step 1: Create local and distributed tables

Connect to the first shard (port 9000) and run:
```sql
SET enable_analyzer = 1;
CREATE TABLE local_table ENGINE = Memory() AS SELECT * FROM numbers(2);
```

Connect to the second shard (port 9001) and run:
```sql
SET enable_analyzer = 1;
CREATE TABLE local_table ENGINE = Memory() AS SELECT * FROM numbers(2);
```

On either shard, create the Distributed table:
```sql
CREATE TABLE distributed_table AS local_table
ENGINE = Distributed('test_cluster_two_shards', currentDatabase(), 'local_table', rand());
```

**Note:** The `enable_analyzer=1` setting is required — the bug only manifests with the new query analyzer enabled.

## Step 2: Query with optimize_skip_unused_shards = 0

```sql
SET enable_analyzer = 1;
SET optimize_skip_unused_shards = 0;
SELECT count() FROM (SELECT DISTINCT number FROM distributed_table);
```

Expected result: **2** (correct — there are 2 distinct values: 0, 1).

## Step 3: Query with optimize_skip_unused_shards = 1

```sql
SET enable_analyzer = 1;
SET optimize_skip_unused_shards = 1;
SELECT count() FROM (SELECT DISTINCT number FROM distributed_table);
```

Observed result: **4** (incorrect — DISTINCT deduplication across shards is skipped).

## Expected result (bug present)
The two queries return different values (2 vs 4). The second result is wrong.
