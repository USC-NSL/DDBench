# Solution: ClickHouse #78074

## Fix
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/78074
- **Fix commit:** `1b768fe2b4695dbb5d6b7534fe881e812852cb45`

## Root cause

When a JOIN query has a condition that is always false (`JOIN ON 0` or `JOIN ON FALSE`), the query optimizer recognizes that no rows will match. However, when the right table is a Distributed table with sorting settings applied, the pipeline still produces Chunk objects from the right side. These chunks have inconsistent row counts — the column data has been filtered or truncated due to the false condition, but the Chunk metadata still reflects the original row count from the sorted stream. This mismatch causes the LOGICAL_ERROR about invalid number of rows.

The specific code path involves right table sorting producing non-empty chunks that then get processed by the JOIN operator which expects empty results for a false join condition. The LowCardinality column type exacerbates the issue because its dictionary-based encoding adds complexity to the chunk row counting.

## Fix description

The fix adds proper handling for the `JOIN ON FALSE` case when right table sorting is active. When the join condition is statically false, the pipeline correctly produces empty chunks regardless of sorting settings, preventing the row count mismatch.

## Files changed

- Test files added to validate the `JOIN ON FALSE` behavior with right table sorting settings and Distributed tables, ensuring that the combination of LowCardinality columns, Distributed engine, and false join conditions produces correct (empty) results.

## How to apply the fix
```bash
cd ClickHouse
git checkout 1b768fe2b4695dbb5d6b7534fe881e812852cb45
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
ninja clickhouse-server clickhouse-client
```
