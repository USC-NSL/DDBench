# Solution: ClickHouse #92375

## Fix
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/92375
- **PR:** https://github.com/ClickHouse/ClickHouse/pull/92634

## Root cause

When `optimize_skip_unused_shards = 1` is enabled, ClickHouse rewrites queries to target individual shards. In doing so, the DISTINCT deduplication step that normally merges results across shards is bypassed. Each shard independently returns its own distinct set, and the results are concatenated without a final deduplication pass on the initiator node.

With two shards each holding `(1, 2)`, each shard returns 2 rows after local DISTINCT, and the initiator concatenates them to get 4 rows instead of deduplicating to get the correct 2.

This is considered "by design" behavior of `optimize_skip_unused_shards` when the sharding key is not part of the DISTINCT columns, but it produces silently wrong results.

## Fix description

The fix is documented as a known limitation: `optimize_skip_unused_shards` should not be used with DISTINCT queries where the sharding key does not match the DISTINCT columns. The workaround is to either:

1. Disable `optimize_skip_unused_shards` for queries involving DISTINCT:
   ```sql
   SET optimize_skip_unused_shards = 0;
   ```
2. Use a subquery with GROUP BY instead of DISTINCT, which forces proper aggregation across shards.
3. Ensure the sharding expression matches the DISTINCT column list.

## How to verify the fix
```bash
clickhouse-client -q "SET optimize_skip_unused_shards=0; SELECT count() FROM (SELECT DISTINCT number FROM distributed_table)"
# Returns 2 (correct)
```
