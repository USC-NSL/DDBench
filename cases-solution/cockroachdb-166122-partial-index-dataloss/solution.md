# Solution: CockroachDB #166122

## Fix
- **Issue:** https://github.com/cockroachdb/cockroach/issues/166122
- **PR:** https://github.com/cockroachdb/cockroach/pull/166123
- **Commit:** `8c90d1ad0b59f18926d3b77f9f653d942f755e36`

## Root cause

Two optimizer normalization rules incorrectly fire during schema change backfills:

1. **`PruneMutationFetchCols`**: This rule prunes columns from mutation fetch operations that it considers unnecessary. During a partial index backfill, it incorrectly prunes columns from other column families that are needed by concurrent DML operations. This causes UPDATE statements to lose track of existing values in other column families, writing NULLs instead.

2. **`SimplifyPartialIndexProjections`**: This rule simplifies projections related to partial index predicates. During backfill, it may incorrectly remove writes to columns that are part of the partial index predicate, causing phantom rows or missing index entries.

Both rules assume they are operating on a stable schema, but during a schema change backfill, the schema is in a transitional state where additional columns may need to be fetched and written.

## Fix description

Disable both `PruneMutationFetchCols` and `SimplifyPartialIndexProjections` optimizer rules when the mutation is part of a schema change backfill:

```go
// In the optimizer rule matching logic:
// Do not apply PruneMutationFetchCols during schema change backfills
if isSchemaChangeBackfill(mutation) {
    return false  // skip this optimization
}

// Do not apply SimplifyPartialIndexProjections during schema change backfills
if isSchemaChangeBackfill(mutation) {
    return false  // skip this optimization
}
```

This ensures that all column families are properly fetched and written during concurrent DML + index backfill operations.

## How to apply
```bash
git checkout 8c90d1ad0b59f18926d3b77f9f653d942f755e36
make build
```

## How to verify
Run the reproduction script with concurrent `CREATE INDEX ... WHERE ...` and `UPDATE` operations. Verify that no NULL values appear in NOT NULL columns and all written values are correctly persisted.
