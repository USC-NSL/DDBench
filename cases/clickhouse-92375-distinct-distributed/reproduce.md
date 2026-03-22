# Reproduce: ClickHouse #92375

## Prerequisites
A running ClickHouse cluster with at least two shards (see setup.md).

## Step 1: Create local and distributed tables

Connect to the first shard (port 9000) and run:
```sql
CREATE TABLE local_table (number UInt64) ENGINE = Memory;
INSERT INTO local_table VALUES (1), (2);
```

Connect to the second shard (port 9001) and run:
```sql
CREATE TABLE local_table (number UInt64) ENGINE = Memory;
INSERT INTO local_table VALUES (1), (2);
```

On either shard, create the Distributed table:
```sql
CREATE TABLE distributed_table AS local_table
ENGINE = Distributed('test_cluster_two_shards', currentDatabase(), 'local_table', rand());
```

## Step 2: Query with optimize_skip_unused_shards = 0

```sql
SET optimize_skip_unused_shards = 0;
SELECT count() FROM (SELECT DISTINCT number FROM distributed_table);
```

Expected result: **2** (correct — there are 2 distinct values: 1, 2).

## Step 3: Query with optimize_skip_unused_shards = 1

```sql
SET optimize_skip_unused_shards = 1;
SELECT count() FROM (SELECT DISTINCT number FROM distributed_table);
```

Observed result: **4** (incorrect — DISTINCT deduplication across shards is skipped).

## Expected result (bug present)
The two queries return different values (2 vs 4). The second result is wrong.
