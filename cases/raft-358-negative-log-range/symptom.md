# Symptom

After a node receives a snapshot from the leader and later takes its own snapshot, the log store encounters an error during the post-snapshot cleanup phase. Depending on the log store implementation, this may manifest as a panic, a logged error from the storage backend, or silently unbounded log growth.

## Observable behavior
- The issue occurs during the log compaction step that follows a successful snapshot.
- Clusters where nodes frequently restart or lag behind (triggering snapshot-based catch-up) are most susceptible.
- The storage-layer error originates from an invalid argument passed to the log store's range-deletion API.
