# Verification: hashicorp/raft #460

## Test procedure

1. Set up the raft source at the buggy commit (see setup.md).

2. Inject the test file into the raft source directory:
   ```bash
   cp inject_test.go logcache_store_order_bug_test.go
   ```

3. Run the unit test:
   ```bash
   go test -v -run "^TestLogCacheStaleDataOnStoreError$" -count=1 .
   ```

4. Evaluate the result.

## Verdict criteria

- **FAIL (bug present):** The test fails because `GetLog(5)` returns a cached entry that was never persisted to the backend store. LogCache populated the ring buffer before calling the backend's `StoreLogs()`, so the cache contains stale data from a failed write. The test output includes "BUG DETECTED: GetLog(5) returned a cached entry".

- **PASS (bug fixed):** The test passes because `GetLog(5)` returns `ErrLogNotFound`. LogCache only populates the ring buffer after the backend's `StoreLogs()` succeeds, so failed writes do not pollute the cache. The test output includes "CORRECT: GetLog(5) returned ErrLogNotFound".

- **Note:** This bug is deterministic -- the test does not depend on timing or concurrency. It directly exercises the cache-before-store vs store-before-cache ordering in `LogCache.StoreLogs()`. A single run is sufficient for verification.
