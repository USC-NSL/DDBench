# Symptom

After compaction removes all revisions of a key except its tombstone (delete marker), restarting etcd causes the tombstone to be lost. A watch starting from a revision at or before the delete never receives the delete event.

## Observable behavior
- A client puts a key, then deletes it.
- Compaction is run at the delete revision, removing all prior put revisions but leaving the tombstone in the database.
- etcd restarts (or the store is restored from the backend).
- After restart, the tombstone is missing from the in-memory key index.
- A watch starting from before the delete revision never delivers the DELETE event for that key.
- This violates the watch guarantee: a deletion that was persisted and not yet compacted away must still be observable via watch.
