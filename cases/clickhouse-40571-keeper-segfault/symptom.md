# Symptom

## Description

ClickHouse Keeper v22.7, when run as a standalone service (not embedded in clickhouse-server), crashes with a segfault (signal 11) on every startup attempt. The crash occurs during initialization, before the Keeper starts accepting client connections.

## Observable behavior

- Starting `clickhouse-keeper` or the Keeper Docker container results in an immediate crash.
- The process exits with signal 11 (SIGSEGV).
- Logs show the Keeper beginning initialization (loading snapshots, preprocessing logs) before the segfault.
- The crash happens consistently on every startup attempt — it is not intermittent.
- The crash trace points to the snapshot installation and log preprocessing phase during Keeper startup.
- Restarting the container or process does not help; the same crash recurs.
- The issue affects standalone Keeper mode specifically; embedded Keeper within `clickhouse-server` may or may not be affected.

## Impact

ClickHouse Keeper v22.7 is completely unusable in standalone mode. Any cluster relying on standalone Keeper for coordination (distributed DDL, replicated tables) cannot start or recover.
