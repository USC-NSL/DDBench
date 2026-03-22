# Symptom: ClickHouse #44865

## Description

On a replicated ClickHouse cluster under sustained write load, background merges on one or more replicas stop permanently. Parts accumulate without being merged, eventually hitting the `parts_to_throw_insert` limit and rejecting new inserts. The only recovery is restarting the affected ClickHouse node.

## Observable behavior

- `system.merges` shows no active merges on the affected replica, despite hundreds of parts.
- `system.replication_queue` may show merge entries stuck in the queue indefinitely.
- `SELECT count() FROM system.parts WHERE active AND table = 'your_table'` shows a continuously growing number of parts.
- Eventually, inserts fail with:
  ```
  Code: 252. DB::Exception: Too many parts (N). Merges are processing
  significantly slower than inserts.
  ```
- The other replica in the same shard continues to merge normally.
- The issue develops over hours or days of sustained write load.
- Restarting the affected ClickHouse node temporarily fixes the problem, but it recurs.
- The `clickhouse-server` log may show no errors related to merges — they simply stop being scheduled.

## Impact

Production replicated tables stop accepting writes once the parts count exceeds the threshold. Without monitoring, this can go undetected until the table becomes read-only.
