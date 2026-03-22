# Reproduce: ClickHouse #78074

## Prerequisites
- ClickHouse server running with a cluster config (see setup.md)
- `clickhouse-client` available

## Step 1: Create local MergeTree tables

```sql
CREATE TABLE t1 (id UInt64, val LowCardinality(String))
ENGINE = MergeTree()
ORDER BY id;

CREATE TABLE t2 (id UInt64, val LowCardinality(String))
ENGINE = MergeTree()
ORDER BY id;
```

## Step 2: Create Distributed tables

```sql
CREATE TABLE t1_dist AS t1
ENGINE = Distributed('test_cluster', currentDatabase(), 't1');

CREATE TABLE t2_dist AS t2
ENGINE = Distributed('test_cluster', currentDatabase(), 't2');
```

## Step 3: Insert data

Insert a substantial number of rows to ensure chunks are created:
```sql
INSERT INTO t1 SELECT number, toString(number) FROM numbers(10000);
INSERT INTO t2 SELECT number, toString(number) FROM numbers(10000);
```

## Step 4: Execute the failing JOIN query

```sql
SELECT count()
FROM t1_dist
JOIN t2_dist ON 0
SETTINGS join_use_nulls = 1;
```

## Expected result (bug present)

The query fails with:
```
Code: 49. DB::Exception: Invalid number of rows in Chunk
```

The error is a LOGICAL_ERROR indicating the internal chunk data structure has a row count mismatch, triggered by the combination of JOIN ON FALSE, Distributed table, and LowCardinality column handling with right table sorting.

## Expected result (bug absent)

The query returns `0` (since JOIN ON FALSE produces no matching rows).
