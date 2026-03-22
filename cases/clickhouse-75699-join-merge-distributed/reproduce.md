# Reproduce: ClickHouse #75699

## Prerequisites
- ClickHouse server running with a cluster configuration (see setup.md)
- `clickhouse-client` available

## Step 1: Create the base tables

```sql
CREATE TABLE a (id UInt64, value String)
ENGINE = MergeTree()
ORDER BY id;

CREATE TABLE b (id UInt64, info String)
ENGINE = MergeTree()
ORDER BY id;
```

## Step 2: Create a Distributed table over table `a`

```sql
CREATE TABLE aa AS a
ENGINE = Distributed('test_cluster', currentDatabase(), 'a');
```

## Step 3: Create a Merge table that covers the Distributed table

```sql
CREATE TABLE m AS a
ENGINE = Merge(currentDatabase(), '^aa$');
```

## Step 4: Insert test data

```sql
INSERT INTO a VALUES (1, 'hello'), (2, 'world');
INSERT INTO b VALUES (1, 'info1'), (2, 'info2');
```

## Step 5: Execute the JOIN query

```sql
SELECT * FROM m JOIN b ON m.id = b.id;
```

## Expected result (bug present)

The query fails with:
```
Code: 49. DB::Exception: LOGICAL_ERROR
```

The error is related to an invalid column source node after `IColumn::forEachSubcolumn` processing.

## Expected result (bug absent)

The query returns:
```
┌─id─┬─value─┬─b.id─┬─info──┐
│  1 │ hello │    1 │ info1 │
│  2 │ world │    2 │ info2 │
└────┴───────┴──────┴───────┘
```
