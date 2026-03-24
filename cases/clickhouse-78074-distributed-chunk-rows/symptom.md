# Symptom

## Description

When executing a JOIN query involving a Distributed table with LowCardinality columns and specific sorting settings, ClickHouse fails with a `LOGICAL_ERROR` about an invalid number of rows in a Chunk. The error occurs during query execution, not during parsing.

## Observable behavior

- A JOIN query against a Distributed table fails with:
  ```
  Code: 49. DB::Exception: Invalid number of rows in Chunk
  ```
- The issue specifically manifests when:
  - The right table in a JOIN is a Distributed table
  - The table has LowCardinality columns
  - The JOIN condition evaluates to `FALSE` (e.g., `JOIN ON 0`)
  - Right table sorting settings are active
- Simpler JOIN conditions (non-false) may work fine.
- The same query against local MergeTree tables (without the Distributed layer) does not crash.

## Impact

Queries involving JOIN ON FALSE patterns with Distributed tables produce internal errors. This can affect query patterns used in automated SQL generation or conditional JOINs.
