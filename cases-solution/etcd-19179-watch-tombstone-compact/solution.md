# Solution: etcd #19179

## Fix
- **PR:** https://github.com/etcd-io/etcd/pull/19188
- **Commit:** `83cf7bb4fc621f017fcaa9a735194fcec23420b8`

## Fix locus
- **Component:** MVCC store restore / key index reconstruction
- **Files:** `server/storage/mvcc/key_index.go`, `server/storage/mvcc/kvstore.go`

## Root cause
In `server/storage/mvcc/kvstore.go`, the `restoreIntoIndex()` function processes key-value pairs from the backend database to rebuild the in-memory key index after a restart. The logic has two branches for a key not yet in the index:

```go
if ok {
    // key already in index — handle tombstone or put
} else if !isTombstone(rkv.key) {
    // key NOT in index and NOT a tombstone — restore it
    ki.restore(...)
}
// implicit: key NOT in index AND IS a tombstone — SKIPPED (the bug)
```

When compaction removes all put revisions for a key but leaves the tombstone (because the tombstone itself is at or after the compaction revision), the tombstone becomes the only revision for that key in the database. During restore, this tombstone is encountered as the first (and only) revision for the key. Since the key is not yet in the index (`ok == false`) and it IS a tombstone (`!isTombstone()` is false), the entire entry is silently skipped. The key index never learns about this delete, so the event is permanently lost.

## Fix description
The fix adds a new `restoreTombstone()` method to `keyIndex` and modifies the restore logic to handle the case of a tombstone being the first revision for a key:

In `key_index.go` (+9 lines):
```go
func (ki *keyIndex) restoreTombstone(lg *zap.Logger, main, sub int64) {
    ki.restore(lg, Revision{}, Revision{main, sub}, 1)
    ki.generations = append(ki.generations, generation{})
    keysGauge.Dec()
}
```

In `kvstore.go` (+6, -2 lines):
```go
// Before (buggy):
} else if !isTombstone(rkv.key) {
    ki.restore(lg, Revision{Main: rkv.kv.CreateRevision}, rev, rkv.kv.Version)
    idx.Insert(ki)
    kiCache[rkv.kstr] = ki
}

// After (fixed):
} else {
    if isTombstone(rkv.key) {
        ki.restoreTombstone(lg, rev.Main, rev.Sub)
    } else {
        ki.restore(lg, Revision{Main: rkv.kv.CreateRevision}, rev, rkv.kv.Version)
    }
    idx.Insert(ki)
    kiCache[rkv.kstr] = ki
}
```

The tombstone is now restored with an empty creating revision (since the original create was already compacted away) and an extra empty generation appended (since a tombstone ends a generation). The `keysGauge.Dec()` call corrects the metric since `restore()` increments it but a tombstone means the key is deleted.

## Diagnosis chain
1. **Runtime evidence:** A watch created before a delete revision does not deliver the DELETE event after etcd restarts with compaction at the delete revision. The watch silently loses the event.
2. **Narrowing the component:** The event is present before restart but absent after. This points to the MVCC restore path, not the watch subsystem itself. The tombstone exists in the bolt database but is missing from the in-memory key index after restore.
3. **Code-level reasoning:** In `restoreIntoIndex()`, the `else if !isTombstone()` guard filters out tombstones that are the first (and only) revision for a key. The fix changes this to an `else` block that handles both tombstones and regular entries for keys not yet in the index.

## Key files
- `server/storage/mvcc/key_index.go` (+9) -- new `restoreTombstone()` method
- `server/storage/mvcc/kvstore.go` (+6, -2) -- handle tombstone-only keys during restore
- `server/storage/mvcc/key_index_test.go` (+41) -- unit test for `restoreTombstone()`
- `server/storage/mvcc/kv_test.go` (+18, -2) -- restore test with tombstone-only key
- `tests/e2e/watch_test.go` (+74) -- e2e test for watch after compaction on tombstone

## How to apply
```bash
git checkout 83cf7bb4fc621f017fcaa9a735194fcec23420b8
make build
```
