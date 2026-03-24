# Symptom

When running Dragonfly in cluster mode, sending a `DFLYCLUSTER CONFIG` command
with very large integer values causes the process to crash.

## Observable behavior
- The Dragonfly process terminates with SIGABRT.
- The crash is triggered by a single cluster configuration command with extreme values.
- Any connected clients are disconnected.
