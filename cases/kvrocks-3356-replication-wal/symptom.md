# Symptom

When a replica stops consuming the replication stream (network congestion, a stalled or overloaded replica process) while its TCP connection stays open, the master never gives up on it.

## Observable behavior
- The master keeps listing the replica under `INFO replication` (`connected_slaves:1`, `slave0:...`) indefinitely, although no replication data reaches it. In production this lasted 44 hours.
- The master's send queue on the replication connection stays full and does not drain.
- Nothing is logged on the master during the stall: no error, no warning, no timeout.
- Client writes on the master keep succeeding, so the replica falls further and further behind.
- When the stall finally ends, WAL files for the replica's position may already have been pruned. The master then logs:
  ```
  Fatal error encountered, WAL iterator is discrete, some seq might be lost, sequence <N> expected, but got <M>
  ```
  The replica's partial resync then fails with `sequence out of range`, and a full resync is forced.

## Expected behavior
A master should detect a replica that has stopped consuming and detach it within a bounded time, while its position is still in the WAL. When the replica becomes responsive again, it should reconnect and catch up.
