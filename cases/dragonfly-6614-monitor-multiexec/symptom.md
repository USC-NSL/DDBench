# Symptom

Calling `MONITOR` twice inside a `MULTI/EXEC` block causes the Dragonfly process to crash with SIGABRT.

## Observable behavior
- The process terminates with an assertion failure.
- A single `MONITOR` inside `MULTI/EXEC` works fine; the crash requires two `MONITOR` commands in the same transaction.
