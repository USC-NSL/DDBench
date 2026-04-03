# Symptom

ZooKeeper server fails to restart after loading a fuzzy snapshot, crashing with a fatal RuntimeException referencing an invalid or missing ACL entry.

## Observable behavior

- Server crashes during startup while loading a fuzzy snapshot.
- The fatal error is a `RuntimeException` indicating that an ACL lookup failed for a znode during snapshot recovery.
- The crash is associated with concurrent write activity (creates and deletes) that was happening while the snapshot was being taken.
- The server cannot recover without manual intervention (deleting snapshot files from the data directory).
- After manual cleanup, the server starts but with potential data loss from the removed snapshot.

## Impact

- Complete service outage on the affected node
- Requires manual intervention to restore service
- Potential data loss if snapshot files must be deleted to recover
