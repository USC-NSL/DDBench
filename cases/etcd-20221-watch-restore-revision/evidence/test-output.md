# Test Output

Obtained by running `go test -v -run "^TestWatchRestoreFutureRevisionBug$" -count=1 -timeout 60s ./server/storage/mvcc/` against the buggy build.

## Output

```
=== RUN   TestWatchRestoreFutureRevisionBug
    logger.go:146: 2026-04-03T11:34:45.445Z	INFO	kvstore restored	{"current-rev": 1}
    logger.go:146: 2026-04-03T11:34:45.950Z	INFO	kvstore restored	{"current-rev": 2}
    watchable_store_restore_bug_test.go:74: Bug present: future-revision watcher (startRev=4) received 1 event(s) after restore. First event at revision 3, but watch starts at rev 4. The watcher's minRev was incorrectly lowered during post-restore resync.
--- FAIL: TestWatchRestoreFutureRevisionBug (3.01s)
FAIL
FAIL	go.etcd.io/etcd/server/v3/storage/mvcc	3.023s
FAIL
```
