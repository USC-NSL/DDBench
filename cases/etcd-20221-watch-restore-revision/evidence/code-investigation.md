# Code Investigation

## What was searched
The symptom describes watches receiving events below their requested start revision after a snapshot restore. A developer would investigate how watchers are re-synced after restore and whether the `minRev` is properly guarded.

## What was found

After a snapshot restore, all synced watchers are moved to the unsynced group:

```go
// server/storage/mvcc/watchable_store.go:204-217
func (s *watchableStore) Restore(b backend.Backend) error {
    s.mu.Lock()
    defer s.mu.Unlock()
    err := s.store.Restore(b)
    if err != nil {
        return err
    }

    for wa := range s.synced.watchers {
        wa.restore = true
        s.unsynced.add(wa)
    }
    s.synced = newWatcherGroup()
    return nil
}
```

When `syncWatchers()` later processes these watchers, it unconditionally sets `minRev`:

```go
// server/storage/mvcc/watchable_store.go:373
w.minRev = curRev + 1
```

The full loop in `syncWatchers()`:

```go
// server/storage/mvcc/watchable_store.go:367-405
for w := range wg.watchers {
    if w.minRev < compactionRev {
        continue
    }
    w.minRev = curRev + 1    // <-- unconditional assignment

    eb, ok := wb[w]
    if !ok {
        s.synced.add(w)
        s.unsynced.delete(w)
        continue
    }
    ...
}
```

There is no guard like `w.minRev = max(curRev+1, w.minRev)`. After a snapshot restore, the store's `currentRev` can be lower than the watcher's original `minRev`. For example, a watcher created with start revision 100 has `minRev=100`. After restoring a snapshot where `currentRev=5`, the assignment `w.minRev = curRev + 1 = 6` regresses the watcher to revision 6, far below its requested start of 100.

Compare with the Watch creation path which does protect against this:

```go
// server/storage/mvcc/watchable_store.go:140-142
wa.minRev = s.store.currentRev + 1
if startRev > wa.minRev {
    wa.minRev = startRev     // <-- guarded with max()
}
```

## Developer hypothesis
The `minRev` assignment logic in `syncWatchers()` compared with the `minRev` assignment logic in the Watch creation path.
