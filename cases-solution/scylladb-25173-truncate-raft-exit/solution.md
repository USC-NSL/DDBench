# Solution: ScyllaDB #25173

## Fix
- **PR:** https://github.com/scylladb/scylladb/pull/25174
- **Commit:** `bb922b2aa9dd58de902848d99fde06b9b1c5828a`

## Root cause
During `DROP TABLE` (or `DROP KEYSPACE`), which is a raft-coordinated operation, the truncate step checks for concurrent writes to the table being dropped. If concurrent writes are detected, the code calls `on_internal_error()`, which throws an exception.

The raft applier fiber has a catch-all exception handler that is designed to handle unexpected errors. When it catches this exception, it logs the error and exits the fiber permanently. This is by design for truly fatal errors, but the truncate concurrent-write check is not a fatal condition — it is an expected race that can happen during normal operations.

The call chain:
1. Raft applier processes DROP TABLE command
2. Truncate is executed as part of the drop
3. Truncate check detects concurrent writes → `on_internal_error()` throws
4. Raft applier catch-all catches the exception → exits fiber
5. Node can no longer process raft commands

## Fix description
Change the concurrent-write check during truncate from `on_internal_error()` (which throws an exception) to a log warning. The concurrent writes during a DROP TABLE are an expected race condition and should not be treated as a fatal internal error. Logging a warning is sufficient to flag the condition without crashing the raft applier.

The change is in the truncate implementation:
```cpp
// Before (buggy):
on_internal_error(log, format("concurrent writes detected during truncate of {}", table_name));

// After (fixed):
log.warn("concurrent writes detected during truncate of {}", table_name);
```

## How to apply
```bash
git checkout bb922b2aa9dd58de902848d99fde06b9b1c5828a
git submodule update --init --recursive
./configure.py --mode=dev
ninja build/dev/scylla
```
