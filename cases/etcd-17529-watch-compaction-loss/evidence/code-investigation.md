# Code Investigation

## What was searched
The symptom describes a watcher silently losing its compaction notification when the watch channel is full. A developer would investigate how `syncWatchers()` handles the case where a compacted watcher's notification fails to send.

## What was found

In `syncWatchers()` (server/storage/mvcc/watchable_store.go), every watcher's `minRev` is unconditionally advanced before attempting to send:

```go
// server/storage/mvcc/watchable_store.go:370-404
victims := make(watcherBatch)
wb := newWatcherBatch(wg, evs)
for w := range wg.watchers {
    w.minRev = curRev + 1           // <-- unconditionally advances past compacted range

    eb, ok := wb[w]
    if !ok {
        // bring un-notified watcher to synced
        s.synced.add(w)
        s.unsynced.delete(w)
        continue
    }

    if eb.moreRev != 0 {
        w.minRev = eb.moreRev
    }

    if w.send(WatchResponse{WatchID: w.id, Events: eb.evs, Revision: curRev}) {
        pendingEventsGauge.Add(float64(len(eb.evs)))
    } else {
        w.victim = true             // <-- send failed, but minRev already advanced
    }

    if w.victim {
        victims[w] = eb
    } else {
        if eb.moreRev != 0 {
            continue
        }
        s.synced.add(w)
    }
    s.unsynced.delete(w)
}
s.addVictim(victims)
```

When a watcher's send fails (channel full), the watcher is marked as a victim. However, `w.minRev` was already set to `curRev + 1` at line 373, which is past the compaction revision. When the victim is later retried (lines 277-325 in the same file), it processes from the already-advanced `minRev`, permanently skipping the compaction notification range.

The victim retry path at lines 277-312:

```go
for _, wb := range victims {
    for w, eb := range wb {
        // watcher has observed the store up to, but not including, w.minRev
        rev := w.minRev - 1
        ...
        w.victim = false
        if eb.moreRev != 0 {
            w.minRev = eb.moreRev
        }
        if w.minRev <= curRev {
```

## Developer hypothesis
The `minRev` assignment relative to the `send()` call within the `syncWatchers()` loop iteration.
