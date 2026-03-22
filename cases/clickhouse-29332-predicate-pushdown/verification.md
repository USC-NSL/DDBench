# Verification: ClickHouse #29332

## Test procedure

1. Start a two-shard ClickHouse cluster (see setup.md).

2. Set up the tables on shard 1:
   ```bash
   clickhouse-client --port 9000 -q "
   CREATE TABLE IF NOT EXISTS local_t1 (id UInt64, value String) ENGINE = MergeTree() ORDER BY id;
   CREATE TABLE IF NOT EXISTS local_t2 (id UInt64, name String) ENGINE = MergeTree() ORDER BY id;
   CREATE TABLE IF NOT EXISTS dist_t1 AS local_t1 ENGINE = Distributed('test_cluster', currentDatabase(), 'local_t1', id);
   CREATE TABLE IF NOT EXISTS dist_t2 AS local_t2 ENGINE = Distributed('test_cluster', currentDatabase(), 'local_t2', id);
   INSERT INTO local_t1 VALUES (1, 'a'), (2, 'b'), (3, 'c');
   INSERT INTO local_t2 VALUES (1, 'alpha'), (2, 'beta');
   "
   ```

   Set up local tables on shard 2:
   ```bash
   clickhouse-client --port 9001 -q "
   CREATE TABLE IF NOT EXISTS local_t1 (id UInt64, value String) ENGINE = MergeTree() ORDER BY id;
   CREATE TABLE IF NOT EXISTS local_t2 (id UInt64, name String) ENGINE = MergeTree() ORDER BY id;
   "
   ```

3. Run the test query:
   ```bash
   RESULT=$(clickhouse-client --port 9000 -q "
   SELECT id, count()
   FROM dist_t1
   WHERE id IN (SELECT id FROM dist_t2)
   GROUP BY id
   ORDER BY id
   SETTINGS enable_optimize_predicate_expression = 1, distributed_product_mode = 'deny'
   " 2>&1)
   EXIT_CODE=$?
   ```

4. Evaluate:
   ```bash
   if [ $EXIT_CODE -eq 0 ]; then
       echo "PASS: Bug is fixed — predicate pushdown does not create double-distributed subquery"
       echo "Result: $RESULT"
   else
       if echo "$RESULT" | grep -q "DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED"; then
           echo "FAIL: Bug is present — predicate pushdown incorrectly creates double-distributed subquery"
       else
           echo "FAIL: Unexpected error: $RESULT"
       fi
   fi
   ```

5. Cleanup:
   ```bash
   clickhouse-client --port 9000 -q "
   DROP TABLE IF EXISTS dist_t2; DROP TABLE IF EXISTS dist_t1;
   DROP TABLE IF EXISTS local_t2; DROP TABLE IF EXISTS local_t1;
   "
   clickhouse-client --port 9001 -q "
   DROP TABLE IF EXISTS local_t2; DROP TABLE IF EXISTS local_t1;
   "
   ```

## Verdict criteria
- **FAIL (bug present):** Query fails with `DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED` (error code 288).
- **PASS (bug fixed):** Query returns 2 rows with correct counts and exit code 0.
