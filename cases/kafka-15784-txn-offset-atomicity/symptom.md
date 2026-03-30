# Symptom

When a transactional offset commit's log append fails with an exception (not a graceful error via callback), the consumer group's in-memory state retains stale pending offsets that diverge from the persisted transaction log state.

## Observable behavior

- `GroupMetadataManager.storeOffsets` is called with a transactional offset commit (producerId != NO_PRODUCER_ID).
- Inside `storeOffsets`, `group.prepareTxnOffsetCommit(producerId, offsetMetadata)` is called first, which adds pending offset entries to the group's in-memory state.
- Then `appendForGroup` (which calls `replicaManager.appendRecords`) is invoked to write the offset records to the `__consumer_offsets` topic.
- If `appendRecords` throws an exception (e.g., due to an I/O error, storage failure, or internal error), the `putCacheCallback` is never invoked.
- Without the callback, `group.failPendingTxnOffsetCommit` is never called, leaving stale pending offsets in memory.
- The group now believes it has pending transactional offsets for the given producer, but no corresponding records exist in the log.
- Subsequent transaction completion (commit or abort) may behave incorrectly because the in-memory state does not match the persisted state.

## Error messages

No explicit error message is produced at runtime. The bug manifests as a silent state divergence that can cause:
- Incorrect offset commits after transaction completion
- Stale offsets visible to consumers
- Potential data loss or duplicate processing if the coordinator fails over and reloads state from the log
