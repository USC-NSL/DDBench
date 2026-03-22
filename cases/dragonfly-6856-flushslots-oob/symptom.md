# Symptom: Dragonfly #6856

When running Dragonfly in cluster mode, sending a `DFLYCLUSTER FLUSHSLOTS` command
with a slot ID that is >= 16384 (the total number of Redis cluster hash slots)
causes the Dragonfly process to crash immediately with a SIGABRT signal.

## Observable behavior
- The Dragonfly process terminates abruptly.
- The crash log shows:
  ```
  Uncaught exception: bitset::set: __position (which is 16384) >= _Nb (which is 16384)
  ```
- A full stack trace is printed via the Abseil failure signal handler, pointing to
  the DFLYCLUSTER FLUSHSLOTS command handler.
- Any connected clients are disconnected.
- If running in production, this means a single malformed cluster management command
  can take down the entire node.
