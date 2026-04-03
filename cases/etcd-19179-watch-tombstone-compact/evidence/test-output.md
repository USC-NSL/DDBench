# Test Output

Obtained by running `go test -v -run "^TestRestoreTombstoneAfterCompaction$" -count=1 -timeout 120s ./server/storage/mvcc/` against the buggy build.

## Output

```
=== RUN   TestRestoreTombstoneAfterCompaction
    logger.go:146: 2026-04-03T11:32:23.724Z	INFO	finished scheduled compaction	{"compact-revision": 7, "took": "10.702943ms", "hash": 1487674969, "current-db-size-bytes": 20480, "current-db-size": "20 kB", "current-db-size-in-use-bytes": 16384, "current-db-size-in-use": "16 kB"}
    logger.go:146: 2026-04-03T11:32:23.724Z	INFO	storing new hash	{"hash": 1487674969, "revision": 7, "compact-revision": -1}
    restore_tombstone_compact_bug_test.go:56: Before close: foo1 key index exists with tombstone at rev 7
    logger.go:146: 2026-04-03T11:32:23.724Z	INFO	restored last compact revision	{"meta-bucket-name-key": "finishedCompactRev", "restored-compact-revision": 7}
    logger.go:146: 2026-04-03T11:32:23.724Z	INFO	kvstore restored	{"current-rev": 7}
    restore_tombstone_compact_bug_test.go:75: Bug present — foo1 has NO key index entry after restore. The tombstone at rev 7 was not reconstructed during restoreIntoIndex. If compaction resumes after a crash, this tombstone will be permanently deleted from the database, causing the delete event to be lost on watches.
--- FAIL: TestRestoreTombstoneAfterCompaction (0.02s)
FAIL
FAIL	go.etcd.io/etcd/server/v3/storage/mvcc	0.031s
FAIL
```
