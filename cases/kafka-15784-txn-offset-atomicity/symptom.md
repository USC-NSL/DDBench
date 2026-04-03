# Symptom

After a storage failure during a transactional offset commit, the consumer group coordinator may retain stale offset state that diverges from what was actually persisted.

## Observable behavior

- A transactional producer commits offsets on behalf of a consumer group.
- A storage-level failure (e.g., I/O error) occurs during the offset commit write.
- The offset commit appears to have partially taken effect: the coordinator behaves as if pending offsets exist, but they were never successfully persisted.
- Subsequent transaction completion (commit or abort) may behave incorrectly because the coordinator's view of pending offsets does not match reality.
- If the coordinator fails over, the new coordinator reloads state from disk and the stale offsets disappear, revealing the inconsistency.

## Error messages

No explicit error message is produced at runtime. The bug manifests as a silent state divergence that can cause:
- Incorrect offset commits after transaction completion
- Stale offsets visible to consumers
- Potential data loss or duplicate processing if the coordinator fails over
