# Symptom

After compaction removes earlier revisions of a key that was subsequently deleted, restarting etcd causes the delete event to become invisible. A watch starting from a revision at or before the delete never receives the delete event.

## Observable behavior
- A client puts a key, then deletes it.
- Compaction is run at the delete revision, removing all prior put revisions.
- etcd restarts.
- After restart, a watch starting from before the delete revision never delivers the DELETE event for that key.
- This violates the watch guarantee: a deletion that was persisted and not yet compacted away must still be observable via watch.
