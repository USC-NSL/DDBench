# Test Output

Obtained by running `cd server && go test -v -timeout 120s -run "TestWatch" ./storage/mvcc/` against the buggy build.

## Output

```
=== RUN   TestWatchableKVWatch
--- PASS: TestWatchableKVWatch (0.25s)
=== RUN   TestWatch
--- PASS: TestWatch (0.01s)
=== RUN   TestWatchCompacted
--- PASS: TestWatchCompacted (0.11s)
=== RUN   TestWatchFutureRev
--- PASS: TestWatchFutureRev (0.01s)
=== RUN   TestWatchRestore
=== RUN   TestWatchRestore/Normal
=== RUN   TestWatchRestore/RunSyncWatchLoopBeforeRestore
--- PASS: TestWatchRestore (2.13s)
=== RUN   TestWatchRestoreSyncedWatcher
--- PASS: TestWatchRestoreSyncedWatcher (2.02s)
=== RUN   TestWatchBatchUnsynced
--- PASS: TestWatchBatchUnsynced (0.31s)
=== RUN   TestWatchVictims
--- PASS: TestWatchVictims (0.44s)
=== RUN   TestWatcherWatchID
--- PASS: TestWatcherWatchID (1.01s)
=== RUN   TestWatcherRequestsCustomID
--- PASS: TestWatcherRequestsCustomID (0.01s)
=== RUN   TestWatcherWatchPrefix
--- PASS: TestWatcherWatchPrefix (0.51s)
=== RUN   TestWatcherWatchWrongRange
--- PASS: TestWatcherWatchWrongRange (0.01s)
=== RUN   TestWatchDeleteRange
--- PASS: TestWatchDeleteRange (0.01s)
=== RUN   TestWatchStreamCancelWatcherByID
--- PASS: TestWatchStreamCancelWatcherByID (0.01s)
=== RUN   TestWatcherRequestProgress
--- PASS: TestWatcherRequestProgress (0.00s)
=== RUN   TestWatcherRequestProgressAll
--- PASS: TestWatcherRequestProgressAll (0.01s)
=== RUN   TestWatcherWatchWithFilter
--- PASS: TestWatcherWatchWithFilter (0.11s)
PASS
ok  	go.etcd.io/etcd/server/v3/storage/mvcc	6.949s
```

All existing watch tests pass, including `TestWatchCompacted` and `TestWatchVictims`. This indicates no existing test covers the scenario where multiple watchers compete for a full channel buffer during compaction notification.
