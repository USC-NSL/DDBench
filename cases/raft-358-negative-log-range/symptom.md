# Symptom

After a snapshot is taken, the log compaction step attempts to call `DeleteRange` with an invalid range where the maximum index is less than the minimum index (e.g., "Compacting logs from 26108 to 6079").

## Observable behavior
- The error is logged during log compaction after a snapshot.
- Depending on the log store implementation, this can cause errors, panics, or silent data corruption.
