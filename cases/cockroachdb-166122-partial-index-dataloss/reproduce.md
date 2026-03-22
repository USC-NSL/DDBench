# Reproduce: CockroachDB #166122

## Prerequisites
A running CockroachDB cluster on the buggy version (see setup.md).

## Reproduction script

Based on the reproduction gist: https://gist.github.com/fqazi/20467eaa1046a1e31082ece6a84a36ae

### Step 1: Create the table with multiple column families

```sql
CREATE TABLE t (
    k INT PRIMARY KEY,
    a INT,
    b INT,
    c INT,
    FAMILY f1 (k, a),
    FAMILY f2 (b),
    FAMILY f3 (c)
);

INSERT INTO t VALUES (1, 10, 20, 30), (2, 11, 21, 31), (3, 12, 22, 32);
```

### Step 2: Start concurrent operations

In one session, create a partial index (this triggers the backfill):
```sql
-- This will take some time on larger tables; the bug occurs during backfill
CREATE INDEX idx_partial ON t(a) WHERE b > 10;
```

In another session, concurrently update rows:
```sql
UPDATE t SET c = 99 WHERE k = 1;
UPDATE t SET b = 55 WHERE k = 2;
UPDATE t SET a = 77, c = 88 WHERE k = 3;
```

### Step 3: Check for data corruption

```sql
SELECT * FROM t ORDER BY k;
```

### Scripted reproduction

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

-- Insert enough rows to make backfill take time
INSERT INTO t SELECT i, i*10, i*20, i*30 FROM generate_series(1, 10000) AS g(i);
SQL

# Start index creation in background
cockroach sql --insecure --host=localhost:26257 -e \
  "CREATE INDEX idx_partial ON t(a) WHERE b > 100;" &
IDX_PID=$!

# Concurrent updates
for i in $(seq 1 100); do
    cockroach sql --insecure --host=localhost:26257 -e \
      "UPDATE t SET c = $((i * 7)) WHERE k = $i;" &
done
wait

# Check for NULLs in NOT NULL columns (corruption indicator)
cockroach sql --insecure --host=localhost:26257 -e \
  "SELECT count(*) AS null_count FROM t WHERE a IS NULL OR b IS NULL OR c IS NULL;"
```

## Expected result (bug present)
The `null_count` query returns a non-zero value, indicating that NOT NULL columns have been corrupted to NULL. Or, values read back do not match what was written.
