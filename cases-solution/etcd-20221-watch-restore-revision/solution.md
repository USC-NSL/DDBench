# Solution: etcd #20221

## Fix
- **PR:** https://github.com/etcd-io/etcd/pull/20281
- **Commit:** `9fb8c3685fd4573e39470a5451d3f85c0f29bfb1`

## Fix locus
- **Component:** MVCC watchable store / watcher resync logic
- **Files:** `server/storage/mvcc/watchable_store.go`, `server/storage/mvcc/watchable_store_test.go`

## Root cause
In `server/storage/mvcc/watchable_store.go`, the `syncWatchers()` function unconditionally sets `w.minRev = curRev + 1` for every watcher in the unsynced group after resync. This assumes all unsynced watchers need to catch up from behind.

However, when `Restore()` is called (as happens when a follower receives a snapshot from the leader), **all** watchers are moved to the unsynced group -- including those watching future revisions that are ahead of `curRev`. When `syncWatchers()` processes these future-revision watchers, it lowers their `minRev` from the originally requested future revision down to `curRev + 1`. This causes the watcher to deliver events with revisions lower than what the client requested, violating the watch contract.

## Fix description
The fix is a one-line change in `syncWatchers()`:

```go
// Before (buggy):
w.minRev = curRev + 1

// After (fixed):
w.minRev = max(curRev+1, w.minRev)
```

By using `max()`, the function preserves the original `minRev` for watchers whose requested start revision is ahead of `curRev`, while still correctly advancing `minRev` for watchers that were behind.

The fix also extracts the hardcoded `100 * time.Millisecond` sync interval into a package-level `watchResyncPeriod` variable and refactors `TestWatchRestore` to cover multiple scenarios including future-revision watchers with and without resync delays.

## Diagnosis chain
1. **Runtime evidence:** A watch created with a future start revision (e.g., rev 100) begins receiving events with revisions well below 100 after a snapshot restore on the follower. The cluster logs show a successful snapshot transfer and restore.
2. **Narrowing the component:** The watch API contract violation points to the MVCC watch layer, not the Raft or transport layer. The bug appears only after a restore, which narrows it to the restore → watcher resync interaction.
3. **Code-level reasoning:** In `watchable_store.go`, `Restore()` moves all watchers to the unsynced group. The `syncWatchers()` function processes unsynced watchers and sets `w.minRev = curRev + 1`, which is correct for watchers behind curRev but destructive for watchers ahead of it. The fix applies `max(curRev+1, w.minRev)` to preserve the original future revision.

## Key files
- `server/storage/mvcc/watchable_store.go` (+6, -4) -- the `syncWatchers()` function and `syncWatchersLoop()`
- `server/storage/mvcc/watchable_store_test.go` (+94, -83) -- regression test covering future-revision watchers after restore

## How to apply
```bash
git checkout 9fb8c3685fd4573e39470a5451d3f85c0f29bfb1
make build
```
