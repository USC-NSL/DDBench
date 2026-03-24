# Symptom

Calling `Raft.Shutdown()` can hang permanently, causing the application to never exit during graceful shutdown.

## Observable behavior
- The application calls `raft.Shutdown()` (e.g., during graceful termination on SIGTERM).
- The call never returns — the application hangs indefinitely.
- The deadlock is permanent — it will never resolve on its own.
- The hang is not deterministic — it depends on timing.
