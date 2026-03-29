# Reproduce: etcd #17529

## Step 1: Inject and run the regression test

The bug is in the mvcc (multi-version concurrency control) watch synchronization layer. It can be reproduced with a unit test that exercises the watchable store directly, without needing a full etcd cluster.

```bash
cd etcd
go test -v -run "^TestWatchNoEventLossOnCompactBug$" -count=1 -timeout 120s ./server/storage/mvcc/
```

The test does the following:
1. Creates a watchable store with a small channel buffer (size 1) and small batch size (4 watchers per sync).
2. Writes 10 revisions of a key, then compacts at revision 5.
3. Creates three watchers: two starting at revision 1 (below compaction) and one starting at revision 6 (above compaction).
4. Calls `syncWatchers()` to process the unsynced watchers.
5. Drains the watch channel, expecting compaction notifications for the two low-revision watchers and normal events for the third.

## Expected result (bug present)

The test times out or fails because one of the two compacted watchers never receives its compaction notification. The channel buffer (size 1) can only hold one compaction response, so the second watcher's notification is dropped. Despite this, the watcher's `minRev` is advanced past the compaction point, permanently losing the notification.

```
FAIL: timed out waiting for all watchers to complete — watcher(s) stuck without compaction notification or events
```
