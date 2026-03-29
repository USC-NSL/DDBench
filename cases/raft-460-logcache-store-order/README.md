# hashicorp/raft #460: LogCache Caches on StoreLogs Error

| Field | Value |
|-------|-------|
| Project | [hashicorp/raft](https://github.com/hashicorp/raft) |
| Issue | [#429](https://github.com/hashicorp/raft/issues/429) |
| Fix PR | [#460](https://github.com/hashicorp/raft/pull/460) |
| Language | Go |
| Category | Data Integrity / Cache Consistency |

## Bug Summary

`LogCache.StoreLogs()` inserts log entries into its in-memory ring buffer BEFORE calling the underlying `store.StoreLogs()`. If the backend store fails (disk error, I/O timeout, etc.), the cache retains entries that were never persisted. Subsequent `GetLog()` calls return these phantom entries, leading the node to believe the logs are durable. On restart, the in-memory cache is lost, and the node panics with "log not found" when NewRaft() tries to read log entries from the backend that were never actually written.

The fix is 3 lines: move the `c.store.StoreLogs()` call before the cache insertion, and only populate the cache on success.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, download deps)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.15+

## What to Expect

**When the bug is present (FAIL):**
The test stores a log entry via LogCache, the backend fails, but GetLog() returns the entry from the stale cache. The test detects this phantom entry and reports FAIL.

**When the bug is fixed (PASS):**
The test stores a log entry via LogCache, the backend fails, and the cache is not populated. GetLog() correctly returns ErrLogNotFound. The test reports PASS.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
