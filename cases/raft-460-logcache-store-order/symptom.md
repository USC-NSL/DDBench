# Symptom

A raft node panics with "log not found" during restart after a previous LogStore backend failure.

## Observable behavior
- A raft node is running with a LogCache wrapping a persistent LogStore backend.
- The backend store experiences a transient failure (disk error, I/O timeout, etc.) during StoreLogs().
- The LogCache's in-memory ring buffer retains the log entries even though StoreLogs() returned an error and the entries were never written to the backend.
- Subsequent GetLog() calls return these phantom entries from the cache, so the node believes the log entries are persisted.
- The node tracks log indices based on the cached (but unpersisted) entries.
- On restart, the in-memory cache is lost. The node calls NewRaft(), which reads log indices from the backend store. It tries to look up a log entry by index and gets "log not found" because the entry was never actually written.
- The node panics with a stack trace originating from `api.go:545` in NewRaft():
  ```
  panic: log not found [recovered]
      panic: log not found
  ```
