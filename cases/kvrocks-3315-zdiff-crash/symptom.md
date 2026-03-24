# Symptom

Sending the command `ZDIFF 0 a` (where numkeys=0) to Kvrocks causes the
server process to crash.

## Observable behavior
- The kvrocks process terminates abruptly.
- Segmentation fault or similar crash signal.
- All client connections are dropped.
