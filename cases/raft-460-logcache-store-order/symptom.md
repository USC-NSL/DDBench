# Symptom

A raft node panics with "log not found" during restart after a previous storage backend failure.

## Observable behavior

- A raft node experiences a transient storage failure (disk error, I/O timeout) during normal operation. The node may or may not log the storage error at the time.
- The node continues operating normally after the transient failure, with no immediate signs of data loss.
- When the node is later restarted, it panics during startup:
  ```
  panic: log not found [recovered]
      panic: log not found
  ```
- The panic occurs because log entries that the node believed were persisted are missing from storage after restart.
- The bug is deterministic: if a storage write fails during operation, the subsequent restart will always panic.
