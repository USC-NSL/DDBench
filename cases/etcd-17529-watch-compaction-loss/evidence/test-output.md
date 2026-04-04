# Test Output

Obtained by running `cd server && go test -v -timeout 120s -run "TestWatch" ./storage/mvcc/` against the buggy build.

## Output

```
=== RUN   TestWatch
--- PASS: TestWatch (0.07s)
=== RUN   TestWatchRestore
--- PASS: TestWatchRestore (0.11s)
=== RUN   TestWatchBatchUnsynced
--- PASS: TestWatchBatchUnsynced (0.13s)
=== RUN   TestWatchCompacted
--- PASS: TestWatchCompacted (0.10s)
=== RUN   TestWatchNoEventLossOnCompact
--- PASS: TestWatchNoEventLossOnCompact (0.00s)
=== RUN   TestWatcherRequestProgress
--- PASS: TestWatcherRequestProgress (0.00s)
=== RUN   TestWatcherRequestProgressAll
--- PASS: TestWatcherRequestProgressAll (0.00s)
=== RUN   TestWatcherWatchWithFilter
--- PASS: TestWatcherWatchWithFilter (0.10s)
PASS
ok  	go.etcd.io/etcd/server/v3/storage/mvcc	6.767s
```

All existing watch tests pass, including `TestWatchCompacted` and `TestWatchNoEventLossOnCompact`. This indicates no existing test covers the scenario where multiple watchers compete for a full channel buffer during compaction notification.
