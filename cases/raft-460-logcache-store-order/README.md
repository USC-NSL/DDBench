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
# from the repository root
./bench.sh setup raft-460-logcache-store-order        # build image + case repository, warm caches
./bench.sh reproduce raft-460-logcache-store-order    # FAIL (exit 1) while the bug is present
./bench.sh shell raft-460-logcache-store-order        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/raft` image; see the top-level README).

## Build Notes

- No build step. The oracle copies `inject_test.go` into package `raft` (it uses package-internal types) and runs it; the test uses only in-memory structures.

## What to Expect

**When the bug is present (FAIL):**
The test stores a log entry via LogCache, the backend fails, but GetLog() returns the entry from the stale cache. The test detects this phantom entry and reports FAIL.

**When the bug is fixed (PASS):**
The test stores a log entry via LogCache, the backend fails, and the cache is not populated. GetLog() correctly returns ErrLogNotFound. The test reports PASS.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
