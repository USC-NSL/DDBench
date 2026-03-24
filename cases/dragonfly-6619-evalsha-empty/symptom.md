# Symptom

Sending `EVALSHA "" 0` (an EVALSHA command with an empty SHA string) to Dragonfly causes the process to crash with SIGABRT.

## Observable behavior
- The crash is immediate upon receiving the command.
- Any connected clients are disconnected.
