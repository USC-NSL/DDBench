# Symptom

ZooKeeper server fails to restart after loading a fuzzy snapshot, crashing with a fatal RuntimeException when trying to access an ACL reference that no longer exists in the cache.

## Observable behavior

- Server crashes during startup while deserializing a fuzzy snapshot
- The fatal error is a `RuntimeException` thrown when attempting to delete a znode whose ACL reference has been purged from the `ReferenceCountedACLCache`
- The crash occurs specifically when a node was deleted and then recreated during the fuzzy snapshot window
- The error message references a missing ACL mapping, causing the server to abort initialization entirely
- The server cannot recover without manual intervention (deleting snapshot files from the data directory)
- After manual cleanup, the server starts but with potential data loss from the removed snapshot

## Impact

- Complete service outage on the affected node
- Requires manual intervention to restore service
- Potential data loss if snapshot files must be deleted to recover
