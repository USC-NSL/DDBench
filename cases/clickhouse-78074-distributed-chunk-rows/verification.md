# Verification: ClickHouse #78074

## Test procedure

1. Start ClickHouse with cluster config (see setup.md).

2. Set up the tables:
   ```bash
   clickhouse-client -q "
   CREATE TABLE IF NOT EXISTS t1 (id UInt64, val LowCardinality(String)) ENGINE = MergeTree() ORDER BY id;
   CREATE TABLE IF NOT EXISTS t2 (id UInt64, val LowCardinality(String)) ENGINE = MergeTree() ORDER BY id;
   CREATE TABLE IF NOT EXISTS t1_dist AS t1 ENGINE = Distributed('test_cluster', currentDatabase(), 't1');
   CREATE TABLE IF NOT EXISTS t2_dist AS t2 ENGINE = Distributed('test_cluster', currentDatabase(), 't2');
   INSERT INTO t1 SELECT number, toString(number) FROM numbers(10000);
   INSERT INTO t2 SELECT number, toString(number) FROM numbers(10000);
   "
   ```

3. Run the test query:
   ```bash
   RESULT=$(clickhouse-client -q "SELECT count() FROM t1_dist JOIN t2_dist ON 0 SETTINGS join_use_nulls = 1" 2>&1)
   EXIT_CODE=$?
   ```

4. Evaluate:
   ```bash
   if [ $EXIT_CODE -eq 0 ] && [ "$RESULT" = "0" ]; then
       echo "PASS: Bug is fixed — JOIN ON FALSE with Distributed tables works correctly"
   else
       echo "FAIL: Bug is present — query returned: $RESULT"
   fi
   ```

5. Cleanup:
   ```bash
   clickhouse-client -q "
   DROP TABLE IF EXISTS t2_dist;
   DROP TABLE IF EXISTS t1_dist;
   DROP TABLE IF EXISTS t2;
   DROP TABLE IF EXISTS t1;
   "
   ```

## Verdict criteria
- **FAIL (bug present):** The query fails with error code 49 (LOGICAL_ERROR) about invalid number of rows in Chunk.
- **PASS (bug fixed):** The query returns `0` with exit code 0.
