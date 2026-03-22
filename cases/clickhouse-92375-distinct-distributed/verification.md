# Verification: ClickHouse #92375

## Automated test

```bash
# Run on a node that can reach both shards
clickhouse-client --port 9000 --multiquery <<'SQL'
SET optimize_skip_unused_shards = 0;
SELECT count() FROM (SELECT DISTINCT number FROM distributed_table);

SET optimize_skip_unused_shards = 1;
SELECT count() FROM (SELECT DISTINCT number FROM distributed_table);
SQL
```

## Pass/fail criteria

- **FAIL (bug present):** The first query returns 2 and the second query returns 4. The two results differ.
- **PASS (bug fixed):** Both queries return **2**.

Alternatively, a scripted check:
```bash
R0=$(clickhouse-client --port 9000 -q "SET optimize_skip_unused_shards=0; SELECT count() FROM (SELECT DISTINCT number FROM distributed_table)")
R1=$(clickhouse-client --port 9000 -q "SET optimize_skip_unused_shards=1; SELECT count() FROM (SELECT DISTINCT number FROM distributed_table)")

if [ "$R0" = "$R1" ] && [ "$R0" = "2" ]; then
    echo "PASS: Bug is fixed"
else
    echo "FAIL: Bug is present (got $R0 vs $R1)"
fi
```
