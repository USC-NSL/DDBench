# Symptom: hashicorp/raft #358

After a snapshot is taken, the log compaction step attempts to call `DeleteRange` with a maximum index that is less than the minimum index (e.g., "Compacting logs from 26108 to 6079"). This results in an invalid range being passed to the log store's `DeleteRange` function.

Depending on the log store implementation, this can cause errors, panics, or silent data corruption. The issue occurs when the snapshot's last included index is behind the current log's first index.
