# Symptom

Sending the command `ZDIFF 0 a` (where numkeys=0) to Kvrocks causes the
server process to crash. The crash is due to an out-of-bounds array access
when the number of keys is zero.

## Observable behavior
- The kvrocks process terminates abruptly.
- Segmentation fault or similar crash signal.
- All client connections are dropped.
