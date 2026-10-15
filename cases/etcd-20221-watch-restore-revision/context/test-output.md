# Test Output

Obtained by running `cd server && go test -v -timeout 60s -run "TestWatch.*Restore" ./storage/mvcc/` against the buggy build.

## Output

```
=== RUN   TestWatchRestore
=== RUN   TestWatchRestore/Normal
=== RUN   TestWatchRestore/RunSyncWatchLoopBeforeRestore
--- PASS: TestWatchRestore (2.40s)
=== RUN   TestWatchRestoreSyncedWatcher
--- PASS: TestWatchRestoreSyncedWatcher (2.01s)
PASS
ok  	go.etcd.io/etcd/server/v3/storage/mvcc	4.168s
```
