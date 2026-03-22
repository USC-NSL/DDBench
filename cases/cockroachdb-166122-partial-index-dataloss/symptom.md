# Symptom: CockroachDB #166122

When a partial index is being backfilled (during `CREATE INDEX ... WHERE ...`) and concurrent UPDATEs are happening on the table, data corruption can occur:

1. **Data loss:** Column values become NULL that were previously non-NULL. A `SELECT` returns NULL for columns that were recently updated with valid values.
2. **Phantom rows:** Rows appear in query results that should not match the partial index predicate, or rows that were updated disappear from query results.
3. **Silent corruption:** No errors are returned to the client during the UPDATE or the index creation. The corruption is only discovered when reading the data back.

This affects tables with multiple column families and partial indexes. The corruption is caused by optimizer rules that incorrectly prune columns during schema change backfills.
