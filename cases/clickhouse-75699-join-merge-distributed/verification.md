# Verification: ClickHouse #75699

## Test procedure

1. Start ClickHouse with cluster config (see setup.md).

2. Set up the tables:
   ```bash
   clickhouse-client -q "
   CREATE TABLE IF NOT EXISTS a (id UInt64, value String) ENGINE = MergeTree() ORDER BY id;
   CREATE TABLE IF NOT EXISTS b (id UInt64, info String) ENGINE = MergeTree() ORDER BY id;
   CREATE TABLE IF NOT EXISTS aa AS a ENGINE = Distributed('test_cluster', currentDatabase(), 'a');
   CREATE TABLE IF NOT EXISTS m AS a ENGINE = Merge(currentDatabase(), '^aa\$');
   INSERT INTO a VALUES (1, 'hello'), (2, 'world');
   INSERT INTO b VALUES (1, 'info1'), (2, 'info2');
   "
   ```

3. Run the test query:
   ```bash
   clickhouse-client -q "SELECT * FROM m JOIN b ON m.id = b.id" 2>&1
   EXIT_CODE=$?
   ```

4. Evaluate:
   ```bash
   if [ $EXIT_CODE -eq 0 ]; then
       echo "PASS: Bug is fixed — JOIN on Merge-over-Distributed works correctly"
   else
       echo "FAIL: Bug is present — LOGICAL_ERROR on JOIN"
   fi
   ```

5. Cleanup:
   ```bash
   clickhouse-client -q "DROP TABLE IF EXISTS m; DROP TABLE IF EXISTS aa; DROP TABLE IF EXISTS b; DROP TABLE IF EXISTS a;"
   ```

## Verdict criteria
- **FAIL (bug present):** The query returns error code 49 (LOGICAL_ERROR).
- **PASS (bug fixed):** The query returns 2 rows with the correct joined data and exit code 0.
