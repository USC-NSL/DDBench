# Reproduce: hashicorp/raft #460

## Prerequisites
- Go 1.15+ installed
- hashicorp/raft checked out at the buggy version (see setup.md)

## Step 1: Inject the test

Copy the test file into the raft source tree:
```bash
cp inject_test.go /path/to/raft/logcache_store_order_bug_test.go
```

The test (`TestLogCacheStaleDataOnStoreError`) does the following:

1. Creates a LogCache wrapping an `errorStore` (an InmemStore wrapper that can inject failures)
2. Pre-populates the backend store with log entries at indices 1..4
3. Arms the errorStore to fail the next StoreLogs() call
4. Calls `c.StoreLog(&Log{Index: 5})` -- the backend fails with an error
5. Verifies that `c.GetLog(5, &out)` returns `ErrLogNotFound` (not the cached entry)

## Step 2: Run the test

```bash
go test -v -run "^TestLogCacheStaleDataOnStoreError$" -count=1 .
```

## Expected result (bug present)

The test FAILs because:
- `LogCache.StoreLogs()` inserts entries into the ring buffer BEFORE calling `c.store.StoreLogs()`
- Even though the backend returns an error, the cache already has the entry at index 5
- `GetLog(5)` returns the cached entry instead of `ErrLogNotFound`
- The test detects this stale cache data and reports:

```
--- FAIL: TestLogCacheStaleDataOnStoreError (0.00s)
    logcache_store_order_bug_test.go: BUG DETECTED: GetLog(5) returned a cached entry (Index=5)
        that was NEVER persisted to the backend store. ...
FAIL
```

## Expected result (bug fixed)

The test PASSes because:
- `LogCache.StoreLogs()` calls `c.store.StoreLogs()` FIRST
- On failure, the cache is not populated
- `GetLog(5)` falls through to the backend, which returns `ErrLogNotFound`

```
--- PASS: TestLogCacheStaleDataOnStoreError (0.00s)
    logcache_store_order_bug_test.go: CORRECT: GetLog(5) returned ErrLogNotFound -- cache was not polluted by failed store
PASS
```
