# Symptom

## Description

When `enable_optimize_predicate_expression` is enabled (the default), queries that combine GROUP BY on a distributed table with a `WHERE id IN (SELECT ... FROM distributed_table)` clause are incorrectly rewritten by the predicate pushdown optimizer. The optimizer pushes the IN predicate containing a distributed subquery down into the distributed table's inner query, effectively creating a double-distributed query that violates `distributed_product_mode='deny'`.

## Observable behavior

- A query like:
  ```sql
  SELECT id, count()
  FROM distributed_table
  WHERE id IN (SELECT id FROM another_distributed_table)
  GROUP BY id
  SETTINGS distributed_product_mode='deny', enable_optimize_predicate_expression=1
  ```
  fails with:
  ```
  Code: 288. DB::Exception: DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED
  ```

- The same query works when `enable_optimize_predicate_expression=0`.
- The same query works when `distributed_product_mode` is set to `'local'` or `'global'` instead of `'deny'`.
- The EXPLAIN output shows the predicate has been incorrectly pushed into the distributed subquery, creating a nested distributed-in-distributed pattern.

## Impact

This silently changes query semantics. With `distributed_product_mode='deny'`, it causes query failures. With other modes, it may produce incorrect results by changing how the IN subquery is distributed, potentially causing data to be filtered against wrong shards.
