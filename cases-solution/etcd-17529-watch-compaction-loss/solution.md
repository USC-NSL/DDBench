# Solution: etcd #17529

- **Issue:** https://github.com/etcd-io/etcd/issues/17529
- **Fix commit:** [`fca3e8a9b5c5b52a65d4ac0fe2fd7fdc7577551a`](https://github.com/etcd-io/etcd/commit/fca3e8a9b5c5b52a65d4ac0fe2fd7fdc7577551a)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/etcd-io/etcd/pull/17555
- **Commit:** `fca3e8a9b5c5b52a65d4ac0fe2fd7fdc7577551a`

## Fix locus
- **Component:** MVCC watchable store / watcher sync logic
- **Files:** `server/storage/mvcc/watchable_store.go`, `server/etcdserver/api/v3rpc/watch.go`

## Root cause
In `server/storage/mvcc/watchable_store.go`, the `syncWatchers()` function iterates over all watchers chosen from the unsynced group and unconditionally sets `w.minRev = curRev + 1` for each one. Before this loop runs, the `choose()` / `chooseAll()` method attempts to send compaction notifications to watchers whose `minRev` is below `compactMainRev`. It sends the compacted response via `w.ch` using a non-blocking select:

```go
select {
case w.ch <- WatchResponse{WatchID: w.id, CompactRevision: compactRev}:
    w.compacted = true
    wg.delete(w)
default:
    // retry next time
}
```

When the channel is full (the `default` branch), the watcher remains in the chosen group without being deleted. Back in `syncWatchers()`, the line `w.minRev = curRev + 1` advances this watcher's revision past the compaction point. On the next sync round, `w.minRev` is now above `compactRev`, so the `w.minRev < compactRev` check in `chooseAll()` evaluates to false and the compaction notification is never retried. The watcher is permanently stuck: it has skipped the compacted range but never told the client about it.

## Fix description
The fix adds a guard in `syncWatchers()` that skips the `w.minRev = curRev + 1` assignment for watchers that still need a compaction notification:

```go
// In syncWatchers(), before w.minRev = curRev + 1:
if w.minRev < compactionRev {
    // Skip the watcher that failed to send compacted watch response due to w.ch is full.
    // Next retry of syncWatchers would try to resend the compacted watch response to w.ch
    continue
}
```

This ensures the watcher's `minRev` stays below the compaction revision, so the next `syncWatchers()` call will retry the compaction notification. The fix also adds a `ChanBufLen()` export function and a gofail injection point in the watch gRPC send path for integration testing.

## Diagnosis chain
1. **Runtime evidence:** A watch client observes that its watch stream silently stops delivering events after a compaction. No compaction error is received. The watch appears stalled indefinitely. This occurs specifically when multiple watchers share a channel and the channel buffer is small relative to the number of compacted watchers.
2. **Narrowing the component:** The watch API is implemented in the MVCC layer (`server/storage/mvcc/`). The compaction notification mechanism is in `watcherGroup.chooseAll()` and the watcher advancement is in `syncWatchers()`. The interaction between these two functions under channel pressure is the failure mode.
3. **Code-level reasoning:** In `watchable_store.go`, `chooseAll()` uses a non-blocking send to deliver compaction notifications. When the send fails, the watcher stays in the group. `syncWatchers()` then advances `w.minRev = curRev + 1` for all watchers in the group, including the one whose compaction send failed. This creates an irreversible state: `w.minRev` is now above `compactRev`, so future sync rounds skip the compaction notification entirely.

## Key files
- `server/storage/mvcc/watchable_store.go` (+7, -0) -- guard in `syncWatchers()` to skip minRev advancement for failed compaction watchers, plus `ChanBufLen()` export
- `server/etcdserver/api/v3rpc/watch.go` (+1, -0) -- gofail injection point for integration testing
- `server/storage/mvcc/watchable_store_test.go` (+58, -0) -- unit test `TestWatchNoEventLossOnCompact`
- `tests/integration/v3_watch_test.go` (+58, -0) -- integration test `TestV3NoEventsLostOnCompact`

## How to apply
```bash
git checkout fca3e8a9b5c5b52a65d4ac0fe2fd7fdc7577551a
make build
```
