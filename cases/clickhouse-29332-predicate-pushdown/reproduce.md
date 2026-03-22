# Reproduce: ClickHouse #29332

## Prerequisites
- Two-shard ClickHouse cluster running (see setup.md)
- `clickhouse-client` available

## Step 1: Create local tables on both shards

Run on both shards (ports 9000 and 9001):
```sql
CREATE TABLE IF NOT EXISTS local_t1 (id UInt64, value String)
ENGINE = MergeTree()
ORDER BY id;

CREATE TABLE IF NOT EXISTS local_t2 (id UInt64, name String)
ENGINE = MergeTree()
ORDER BY id;
```

## Step 2: Create Distributed tables (run on shard 1)

```sql
CREATE TABLE IF NOT EXISTS dist_t1 AS local_t1
ENGINE = Distributed('test_cluster', currentDatabase(), 'local_t1', id);

CREATE TABLE IF NOT EXISTS dist_t2 AS local_t2
ENGINE = Distributed('test_cluster', currentDatabase(), 'local_t2', id);
```

## Step 3: Insert test data (run on shard 1)

```sql
INSERT INTO local_t1 VALUES (1, 'a'), (2, 'b'), (3, 'c');
INSERT INTO local_t2 VALUES (1, 'alpha'), (2, 'beta');
```

## Step 4: Execute the failing query

```sql
SELECT id, count()
FROM dist_t1
WHERE id IN (SELECT id FROM dist_t2)
GROUP BY id
SETTINGS
    enable_optimize_predicate_expression = 1,
    distributed_product_mode = 'deny';
```

## Expected result (bug present)

```
Code: 288. DB::Exception: Double-distributed IN/JOIN subqueries is denied
(distributed_product_mode = 'deny'). ... DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED
```

The predicate pushdown optimizer pushes the `IN (SELECT id FROM dist_t2)` predicate down into the distributed query for `dist_t1`, creating a double-distributed subquery pattern.

## Expected result (bug absent)

The query returns:
```
┌─id─┬─count()─┐
│  1 │       1 │
│  2 │       1 │
└────┴─────────┘
```

## Verification with EXPLAIN

You can confirm the incorrect rewrite with:
```sql
EXPLAIN SYNTAX
SELECT id, count()
FROM dist_t1
WHERE id IN (SELECT id FROM dist_t2)
GROUP BY id
SETTINGS enable_optimize_predicate_expression = 1;
```

In the buggy version, the IN predicate is pushed inside the distributed subquery.
