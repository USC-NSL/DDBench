# Verification: ClickHouse #99109

## Automated test

```bash
clickhouse-client --multiquery <<'SQL'
SELECT count() FROM (
    SELECT
        t1.key,
        t1.s AS sum_threads1,
        t8.s AS sum_threads8
    FROM (
        SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key ORDER BY key
        SETTINGS max_threads = 1
    ) t1
    JOIN (
        SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key ORDER BY key
        SETTINGS max_threads = 8
    ) t8 ON t1.key = t8.key
    WHERE t1.s != t8.s
);
SQL
```

## Pass/fail criteria

- **FAIL (bug present):** The count is greater than 0, meaning some keys have different sums depending on thread count.
- **PASS (bug fixed):** The count is 0, meaning all sums are identical regardless of thread count.

Scripted check:
```bash
DIFF_COUNT=$(clickhouse-client -q "
SELECT count() FROM (
    SELECT t1.key FROM (
        SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key SETTINGS max_threads=1
    ) t1 JOIN (
        SELECT key, sum(value) AS s FROM float_sum_test GROUP BY key SETTINGS max_threads=8
    ) t8 ON t1.key = t8.key WHERE t1.s != t8.s
)")

if [ "$DIFF_COUNT" = "0" ]; then
    echo "PASS: Bug is fixed"
else
    echo "FAIL: Bug is present ($DIFF_COUNT keys have different sums)"
fi
```
