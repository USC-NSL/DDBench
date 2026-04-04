# Code Investigation

## What was searched
The symptom describes a delete event becoming invisible after compaction + restart. A developer would investigate how the key index is rebuilt during restore, specifically how tombstone entries are handled when the prior put revisions have been compacted away.

## What was found

The `restoreIntoIndex` function in `server/storage/mvcc/kvstore.go` has a branch structure that silently drops tombstone-only keys:

```go
// server/storage/mvcc/kvstore.go:432-484
func restoreIntoIndex(lg *zap.Logger, idx index) (chan<- revKeyValue, <-chan int64) {
    ...
    for rkv := range rkvc {
        ki, ok := kiCache[rkv.kstr]
        ...
        // cache miss, fetch from tree index if there
        if !ok {
            ki = &keyIndex{key: rkv.kv.Key}
            if idxKey := idx.KeyIndex(ki); idxKey != nil {
                kiCache[rkv.kstr], ki = idxKey, idxKey
                ok = true
            }
        }
        ...
        if ok {
            if isTombstone(rkv.key) {
                if err := ki.tombstone(lg, rev.Main, rev.Sub); err != nil {
                    lg.Warn("tombstone encountered error", zap.Error(err))
                }
                continue
            }
            ki.put(lg, rev.Main, rev.Sub)
        } else if !isTombstone(rkv.key) {
            ki.restore(lg, Revision{Main: rkv.kv.CreateRevision}, rev, rkv.kv.Version)
            idx.Insert(ki)
            kiCache[rkv.kstr] = ki
        }
        // IMPLICIT: if !ok && isTombstone(rkv.key) => nothing happens, tombstone is dropped
    }
    ...
}
```

The branch logic has three paths:
1. `ok && isTombstone` — tombstone applied to existing keyIndex (line 469-473)
2. `ok && !isTombstone` — put applied to existing keyIndex (line 476)
3. `!ok && !isTombstone` — new keyIndex created and inserted (line 476-479)

The missing fourth case — `!ok && isTombstone` — falls through silently. This case occurs when compaction has removed the put revision for a key, leaving only the delete (tombstone) revision in boltdb. During restore, the tombstone is the first (and only) entry seen for that key, so `ok` is false, and the `else if !isTombstone` guard prevents it from being indexed.

## Developer hypothesis
The branch logic in `restoreIntoIndex` handling the combinations of existing keys and tombstones.
