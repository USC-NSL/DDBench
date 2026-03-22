# Symptom: ClickHouse #92375

When running `SELECT count() FROM (SELECT DISTINCT number FROM distributed_table)` on a Distributed table backed by two shards, the result changes depending on the `optimize_skip_unused_shards` setting:

- With `optimize_skip_unused_shards = 0` (default), the query correctly returns **2** distinct values.
- With `optimize_skip_unused_shards = 1`, the query incorrectly returns **4**, as if DISTINCT deduplication across shards is skipped entirely.

This means the same logical query produces different (wrong) results based on an optimization setting that should only affect performance, not correctness.
