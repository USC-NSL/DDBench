# Reproduce: ClickHouse #99109

## Prerequisites
A running ClickHouse server (see setup.md).

## Step 1: Create table and insert data

```sql
CREATE TABLE float_sum_test (
    key UInt32,
    value Float64
) ENGINE = MergeTree()
ORDER BY key;

-- Insert 200,000 rows with varied Float64 values
INSERT INTO float_sum_test
SELECT
    number % 10 AS key,
    (rand64() / 1e18) AS value
FROM numbers(200000);
```

## Step 2: Query with max_threads = 1

```sql
SET max_threads = 1;
SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key ORDER BY key
FORMAT TabSeparatedWithNamesAndTypes;
```

Record the sum values.

## Step 3: Query with max_threads = 8

```sql
SET max_threads = 8;
SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key ORDER BY key
FORMAT TabSeparatedWithNamesAndTypes;
```

## Step 4: Compare results

```sql
SELECT
    t1.key,
    t1.s AS sum_threads1,
    t8.s AS sum_threads8,
    (t1.s - t8.s) AS diff
FROM (
    SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key ORDER BY key
    SETTINGS max_threads = 1
) t1
JOIN (
    SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key ORDER BY key
    SETTINGS max_threads = 8
) t8 ON t1.key = t8.key
WHERE t1.s != t8.s;
```

## Expected result (bug present)
At least some rows show a non-zero `diff` value. The sums differ between single-threaded and multi-threaded execution.
