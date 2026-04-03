# Test Output

Obtained by running `go test -v -run TestLogCacheStaleDataOnStoreError -count=1 -timeout 30s .` with a test that injects a storage failure into StoreLogs and checks whether the LogCache still serves stale entries, against the buggy build.

## Output

```
=== RUN   TestLogCacheStaleDataOnStoreError
    logcache_store_order_bug_test.go:109: BUG DETECTED: GetLog(5) returned a cached entry (Index=5) that was NEVER persisted to the backend store. The LogCache cached data before verifying the backend write succeeded. On restart, this entry would be lost, causing a 'log not found' panic.
--- FAIL: TestLogCacheStaleDataOnStoreError (0.00s)
FAIL
FAIL	github.com/hashicorp/raft	0.004s
```
