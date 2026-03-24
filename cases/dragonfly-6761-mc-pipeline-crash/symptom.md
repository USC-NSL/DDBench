# Symptom

When using the memcache protocol, sending `STATS` or `VERSION` commands inside a pipeline causes the process to crash.

## Observable behavior
- The crash only occurs when these commands are pipelined (sent together with other commands).
- Sending the same commands individually (not pipelined) works correctly.
- The process terminates with SIGABRT.
