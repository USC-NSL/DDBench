# Reproduce: hashicorp/raft #460

## Prerequisites
- Run inside `./bench.sh shell raft-460-logcache-store-order`, from `/workspace/src` (hashicorp/raft at the buggy commit; the Go toolchain is in the image).
- The test file is the case's `inject_test.go`, mounted at `/bench/inject_test.go`.

## Step 1: Inject the test

Copy the test file into the raft source tree:
```bash
cp /bench/inject_test.go /workspace/src/logcache_store_order_bug_test.go
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

## Oracle verdict

`./bench.sh reproduce raft-460-logcache-store-order` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): the injected test `TestDDBenchOracleLogCacheStoreError` fails: after `StoreLog` of entry 5 through a `LogCache` whose backing store rejects the write with an injected error, `GetLog(5)` still returns the entry instead of `ErrLogNotFound` (the test also fails if the write error is not returned or entries 1–4 become unreadable). A worktree that does not build, or a package or injected test that does not compile (or a skipped test), is also FAIL.
- **PASS** (exit 0): the injected test passes within its 60 s timeout: the failed write is reported, entries 1–4 are readable, and `GetLog(5)` returns `ErrLogNotFound`.
- **ERROR** (exit 2): `REBUILD.sh`, `raft.go` or `inject_test.go` is missing, or the test did not run because a Go module download failed (network).
