# Symptom

## Description

When performing a JOIN query where the left table is a Merge table backed by a Distributed table, ClickHouse crashes with a `LOGICAL_ERROR` exception. The error occurs internally in the query execution pipeline, not due to incorrect SQL syntax.

## Observable behavior

- A `SELECT * FROM merge_table JOIN local_table` query fails with:
  ```
  Code: 49. DB::Exception: LOGICAL_ERROR
  ```
- The error message references an invalid column source node.
- The crash is deterministic — the same query always fails.
- Simpler queries on the Merge table alone (without JOIN) work fine.
- Queries that JOIN the underlying Distributed table directly (bypassing the Merge table) may also work.
- The issue is triggered specifically by the combination of Merge table wrapping a Distributed table in a JOIN context.

## Impact

Any query that JOINs a Merge-over-Distributed table with another table will fail. This prevents use of a common ClickHouse pattern for querying across multiple clusters or databases through Merge tables when JOIN operations are needed.
