# Reproduce: etcd #20221

## Step 1: Inject and run the regression test

The bug is in the mvcc (multi-version concurrency control) layer. It can be reproduced with a unit test that exercises the watchable store directly, without needing a full etcd cluster.

```bash
cd etcd
go test -v -run "^TestWatchRestoreFutureRevisionBug$" -count=1 -timeout 60s ./server/storage/mvcc/
```

The test does the following:
1. Creates a watchable store and writes an initial key.
2. Creates a watch on that key with start revision 100 (a future revision).
3. Calls `Restore()` on the store (simulating a snapshot restore on a follower).
4. Waits for background resync processing.
5. Writes additional entries at low revisions.
6. Checks whether the watcher receives any events with revisions below 100.

## Expected result (bug present)

The test fails because the watcher receives events with revisions far below the requested start revision of 100. For example, events at revision 2 and 3 are delivered to a watcher that should only see events starting from revision 100.

```
FAIL: watcher received event with revision 2, but requested start revision was 100 — watch contract violated after restore
```
