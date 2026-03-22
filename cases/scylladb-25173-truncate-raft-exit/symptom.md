# Symptom: ScyllaDB #25173

When concurrent writes are happening to a table while a `DROP TABLE` or `DROP KEYSPACE` operation is executed, ScyllaDB's raft applier fiber permanently exits. After this happens, the node can no longer execute any raft-based operations (schema changes, topology operations, etc.).

The sequence of events:
1. Writes are ongoing to a table
2. A `DROP TABLE` (or `DROP KEYSPACE`) is executed — this is a raft operation
3. During the drop, a truncate check detects concurrent writes and calls `on_internal_error`, which throws an exception
4. The raft applier fiber catches this exception in its catch-all handler and exits permanently
5. The node appears to be running but cannot process any further raft commands

After the fiber exits, subsequent schema changes (CREATE TABLE, ALTER TABLE, etc.) and topology operations hang indefinitely. The node must be restarted to recover.

Logs show an error similar to:
```
[raft] - Raft applier fiber exited with error: ...truncate check failed...
```
