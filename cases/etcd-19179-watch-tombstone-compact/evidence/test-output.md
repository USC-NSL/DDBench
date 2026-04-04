# Test Output

Obtained by running `cd server && go test -v -timeout 60s ./storage/mvcc/` against the buggy build.

## Output

```
=== RUN   TestWatchBatchUnsynced
--- PASS: TestWatchBatchUnsynced (0.61s)
=== RUN   TestWatchVictims
--- PASS: TestWatchVictims (0.50s)
=== RUN   TestWatchDeleteRange
--- PASS: TestWatchDeleteRange (0.00s)
=== RUN   TestWatcherWatchWithFilter
--- PASS: TestWatcherWatchWithFilter (0.11s)
PASS
ok  	go.etcd.io/etcd/server/v3/storage/mvcc	11.987s
```

All existing mvcc tests pass. No test covers the scenario where compaction removes the put revision, leaving only a tombstone, and then the server restarts and must restore the index from the remaining tombstone-only entry.
