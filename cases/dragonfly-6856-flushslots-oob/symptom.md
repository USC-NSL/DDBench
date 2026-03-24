# Symptom

When running Dragonfly in cluster mode, sending a `DFLYCLUSTER FLUSHSLOTS` command with a slot ID of 16384 or higher causes the process to crash with SIGABRT.

## Observable behavior
- The Dragonfly process terminates abruptly.
- Any connected clients are disconnected.
