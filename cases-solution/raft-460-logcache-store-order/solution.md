# Solution: hashicorp/raft #460

- **Issue:** https://github.com/hashicorp/raft/issues/429
- **Fix commit:** [`f810f43d71b4a051a0c0e16e003f0a55456dd0fb`](https://github.com/hashicorp/raft/commit/f810f43d71b4a051a0c0e16e003f0a55456dd0fb)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/hashicorp/raft/pull/460 (updated version of https://github.com/hashicorp/raft/pull/430)
- **Issue:** https://github.com/hashicorp/raft/issues/429
- **Commit:** `f810f43d71b4a051a0c0e16e003f0a55456dd0fb`

## Fix locus
- **Component:** LogCache write-through layer (`LogCache.StoreLogs`)
- **Files:** `log_cache.go` (+7, -3), `log_cache_test.go` (+60), `raft_test.go` (+50)

## Root cause
In `log_cache.go`, the `StoreLogs()` method populates the in-memory ring buffer **before** calling the underlying backend's `StoreLogs()`. The buggy ordering is:

```go
func (c *LogCache) StoreLogs(logs []*Log) error {
    // 1. Insert into ring buffer FIRST
    c.l.Lock()
    for _, l := range logs {
        c.cache[l.Index%uint64(len(c.cache))] = l
    }
    c.l.Unlock()
    // 2. Then write to backend store
    return c.store.StoreLogs(logs)
}
```

If the backend `StoreLogs()` fails (due to a disk error, I/O timeout, or any transient failure), the entries remain in the cache even though they were never persisted to durable storage. This creates "phantom" log entries: `GetLog()` returns them from the cache, so the raft node believes these entries exist and tracks their indices as committed. However, on node restart the in-memory cache is lost, and `NewRaft()` reads log indices from the backend store. When it tries to look up the phantom entries by index, the backend returns `ErrLogNotFound`, causing the node to panic with `panic: log not found`.

The fundamental issue is a violation of the write-through cache invariant: the cache must never contain entries that are not also present in the backing store. Populating the cache before confirming the backend write succeeds breaks this invariant.

## Diagnosis chain
1. **Runtime observation:** A raft node panics with `panic: log not found [recovered] panic: log not found` during restart (in `NewRaft()` at `api.go:545`). The stack trace shows the node is trying to read a log entry by index from the store, but the entry does not exist. The node had been running with a `LogCache` wrapping a persistent `LogStore`, and the backend had experienced a transient failure during a previous `StoreLogs()` call.
2. **Pattern recognition:** The panic occurs only on restart after a previous backend store failure. This suggests a discrepancy between what the node believed was stored (tracked in-memory) versus what was actually persisted. The `LogCache` layer is the intermediary between raft logic and the persistent store, making it the prime suspect for cache-store inconsistency.
3. **Code reasoning:** Tracing through `LogCache.StoreLogs()` in `log_cache.go`: the method first acquires the lock and inserts all log entries into the ring buffer (`c.cache[l.Index%...]`), then calls `c.store.StoreLogs(logs)`. If the backend call returns an error, the entries are already in the cache. Subsequent `GetLog()` calls check the cache first and find matches, so the raft node never discovers the entries are missing from durable storage. The node continues operating with phantom indices. On restart, the cache is empty (volatile memory), and the backend store lacks the entries, causing the fatal lookup failure.
4. **Root cause confirmed:** The ordering of cache-insert-then-backend-write is the root cause. The cache must only be populated after confirming that the backend write succeeded. This is confirmed by the unit test `TestLogCacheWithBackendStoreError` which injects a backend failure and verifies that `GetLog()` for the failed index returns `ErrLogNotFound` (not a cached phantom entry).

## Fix description
The fix reorders the two operations in `LogCache.StoreLogs()` so that the backend store write happens **first**, and the cache is populated **only on success**:

```go
func (c *LogCache) StoreLogs(logs []*Log) error {
    err := c.store.StoreLogs(logs)
    // Insert the logs into the ring buffer, but only on success
    if err != nil {
        return fmt.Errorf("unable to store logs within log store, err: %q", err)
    }
    c.l.Lock()
    for _, l := range logs {
        c.cache[l.Index%uint64(len(c.cache))] = l
    }
    c.l.Unlock()
    return nil
}
```

This restores the write-through cache invariant: every entry in the cache is guaranteed to also exist in the backend store. If the backend write fails, the cache remains clean, and `GetLog()` correctly falls through to the backend which returns `ErrLogNotFound`. The error message is also wrapped with additional context for debuggability.

## How to apply
```bash
cd raft
git checkout f810f43d71b4a051a0c0e16e003f0a55456dd0fb
```

## How to verify
Run `reproduce.sh` which injects a test (`TestLogCacheStaleDataOnStoreError`) that creates a `LogCache` wrapping an error-injecting store, pre-populates indices 1-4, arms the store to fail the next `StoreLogs()`, attempts to store index 5 (which fails), and then verifies that `GetLog(5)` returns `ErrLogNotFound` rather than a cached phantom entry. With the fix applied, the cache is not polluted by the failed write and the test passes (PASS). Without the fix, `GetLog(5)` returns the cached-but-unpersisted entry and the test fails (FAIL). The bug is deterministic and does not depend on timing or concurrency.
