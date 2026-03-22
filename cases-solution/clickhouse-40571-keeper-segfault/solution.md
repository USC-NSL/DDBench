# Solution: ClickHouse #40571

## Fix
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/40571
- **Fix PR:** https://github.com/ClickHouse/ClickHouse/pull/40627
- **Fix commit:** `cecdcb50598aad333d8cb784b914a19a567e0b88`

## Root cause

During Keeper startup, the initialization sequence involves two key phases: installing the latest snapshot and preprocessing Raft log entries. There is a bug in the interaction between these two phases in v22.7.

When installing a snapshot, the Keeper reads the snapshot data and reconstructs the in-memory state. Subsequently, the log preprocessing phase iterates over log entries to bring the state up to date. The bug is that the snapshot installation does not properly initialize all data structures needed by the preprocessing phase. Specifically, a pointer or reference used during log preprocessing is left in an invalid state after snapshot installation, leading to a null pointer dereference or access to freed memory (segfault).

The crash is deterministic because the same initialization sequence runs on every startup.

## Fix description

The fix corrects the snapshot installation and log preprocessing logic to ensure that:
1. All data structures are properly initialized after snapshot installation before preprocessing begins.
2. The performance of preprocessing is improved to avoid the problematic code path.

## Files changed

- **`src/Coordination/KeeperServer.cpp`** — Fixed the initialization sequence to properly set up state after snapshot installation, ensuring all references are valid before log preprocessing begins.
- **`src/Coordination/KeeperStateMachine.cpp`** — Corrected snapshot installation to fully initialize the state machine before returning control to the log preprocessor.

## How to apply the fix
```bash
cd ClickHouse
git checkout cecdcb50598aad333d8cb784b914a19a567e0b88
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
ninja clickhouse-keeper
```

Or use a fixed Docker image (>= 22.8):
```bash
docker pull clickhouse/clickhouse-keeper:22.8
```
