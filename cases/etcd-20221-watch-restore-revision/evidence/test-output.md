# Test Output

Obtained by running `cd server && go test -v -timeout 60s -run "TestWatch.*Restore" ./storage/mvcc/` against the buggy build.

## Output

```
=== RUN   TestWatchRestore
--- PASS: TestWatchRestore (0.11s)
=== RUN   TestWatchRestoreSyncedWatcher
--- PASS: TestWatchRestoreSyncedWatcher (2.01s)
PASS
ok  	go.etcd.io/etcd/server/v3/storage/mvcc	4.168s
```

Existing watch restore tests pass. No test covers the scenario where a watcher's requested start revision is higher than the restored snapshot's current revision, which would expose the `minRev` regression.
