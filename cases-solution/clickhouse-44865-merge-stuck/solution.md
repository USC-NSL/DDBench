# Solution: ClickHouse #44865

## Fix
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/44865
- **Related root cause:** https://github.com/ClickHouse/ClickHouse/issues/43816

## Root cause

The bug is a deadlock in the interaction between `ReplicatedMergeTreeQueue` and `MergeTreeBackgroundExecutor`. The root cause (tracked in #43816) involves the following scenario:

1. The background merge executor picks up a merge task from the replicated queue.
2. The merge task acquires a lock on the replicated queue to mark parts as being merged.
3. Simultaneously, another thread (e.g., handling replication or queue updates) holds a different lock and tries to interact with the background executor.
4. This creates a lock ordering deadlock: Thread A holds Lock1 and waits for Lock2, while Thread B holds Lock2 and waits for Lock1.

Once the deadlock occurs, no new merges can be scheduled. Existing merges may complete, but the background pool stops picking up new merge tasks. Parts accumulate as inserts continue.

The deadlock is non-deterministic but becomes increasingly likely under sustained write load with concurrent replication activity.

## Fix description

This was fixed across multiple PRs as part of a background pool redesign in later ClickHouse versions. The key changes include:

1. **Lock ordering fix:** Ensured consistent lock acquisition order between `ReplicatedMergeTreeQueue` and `MergeTreeBackgroundExecutor` to prevent the deadlock cycle.
2. **Background executor redesign:** Refactored the background executor to avoid holding locks while calling into the replicated queue, breaking the potential deadlock chain.
3. **Task scheduling improvements:** Changed how merge tasks are scheduled to reduce contention between replication and merge operations.

## Files changed (across multiple PRs)

- **`src/Storages/MergeTree/MergeTreeBackgroundExecutor.cpp`** — Refactored task scheduling to avoid holding executor lock while interacting with replicated queue.
- **`src/Storages/MergeTree/ReplicatedMergeTreeQueue.cpp`** — Changed lock scoping to prevent deadlock with background executor.
- **`src/Storages/StorageReplicatedMergeTree.cpp`** — Updated merge task submission to use the new lock-free scheduling interface.

## Workaround (without code fix)

1. Monitor parts count and restart ClickHouse when merges stop:
   ```bash
   # Cron-based watchdog
   PARTS=$(clickhouse-client -q "SELECT max(c) FROM (SELECT count() as c FROM system.parts WHERE active GROUP BY table)")
   if [ "$PARTS" -gt 200 ]; then
       systemctl restart clickhouse-server
   fi
   ```

2. Upgrade to ClickHouse >= 23.3 where the background pool was redesigned.
