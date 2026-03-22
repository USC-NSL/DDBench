# Verification: CockroachDB #166122

## Automated test

```bash
#!/bin/bash
cockroach sql --insecure --host=localhost:26257 <<'SQL'
DROP TABLE IF EXISTS t;
CREATE TABLE t (
    k INT PRIMARY KEY,
    a INT NOT NULL,
    b INT NOT NULL,
    c INT NOT NULL,
    FAMILY f1 (k, a),
    FAMILY f2 (b),
    FAMILY f3 (c)
);
INSERT INTO t SELECT i, i*10, i*20, i*30 FROM generate_series(1, 10000) AS g(i);
SQL

# Start index creation in background
cockroach sql --insecure --host=localhost:26257 -e \
  "CREATE INDEX idx_partial ON t(a) WHERE b > 100;" &

# Concurrent updates during backfill
sleep 0.5
for i in $(seq 1 200); do
    cockroach sql --insecure --host=localhost:26257 -e \
      "UPDATE t SET c = $((i * 7)) WHERE k = $i;" 2>/dev/null &
done
wait

# Verify data integrity
NULL_COUNT=$(cockroach sql --insecure --host=localhost:26257 --format=csv -e \
  "SELECT count(*) FROM t WHERE a IS NULL OR b IS NULL OR c IS NULL;" | tail -1)

# Also check that values match expected
MISMATCH=$(cockroach sql --insecure --host=localhost:26257 --format=csv -e \
  "SELECT count(*) FROM t WHERE k <= 200 AND c != k * 7 AND c != k * 30;" | tail -1)

if [ "$NULL_COUNT" != "0" ]; then
    echo "FAIL: Bug is present — $NULL_COUNT rows have NULL in NOT NULL columns (data loss)"
elif [ "$MISMATCH" != "0" ]; then
    echo "FAIL: Bug is present — $MISMATCH rows have corrupted values"
else
    echo "PASS: Bug is fixed — no data corruption detected"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** Rows have NULL values in NOT NULL columns, or column values do not match expected results after concurrent UPDATE + partial index creation.
- **PASS (bug fixed):** All NOT NULL columns remain non-NULL, and all values match the expected results after concurrent operations complete.
