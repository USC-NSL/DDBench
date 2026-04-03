# Test Output

Obtained by running `go test -v -run "^TestWatchNoEventLossOnCompactBug$" -count=1 -timeout 120s ./server/storage/mvcc/` against the buggy build.

## Output

```
=== RUN   TestWatchNoEventLossOnCompactBug
    logger.go:130: 2026-04-03T11:27:17.684Z	DEBUG	bbolt	Starting a new transaction [writable: true]
    logger.go:130: 2026-04-03T11:27:17.684Z	DEBUG	bbolt	Starting a new transaction [writable: true] successfully
    logger.go:130: 2026-04-03T11:27:17.684Z	DEBUG	bbolt	Putting key "scheduledCompactRev"
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Putting key "scheduledCompactRev" successfully
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Committing transaction 3
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Committing transaction 3 successfully
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Starting a new transaction [writable: true]
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Starting a new transaction [writable: true] successfully
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Starting a new transaction [writable: false]
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Starting a new transaction [writable: false] successfully
    logger.go:130: 2026-04-03T11:27:17.685Z	INFO	compact tree index	{"revision": 5}
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Deleting key "\x00\x00\x00\x00\x00\x00\x00\x02_\x00\x00\x00\x00\x00\x00\x00\x00"
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Deleting key "\x00\x00\x00\x00\x00\x00\x00\x02_\x00\x00\x00\x00\x00\x00\x00\x00" successfully
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Deleting key "\x00\x00\x00\x00\x00\x00\x00\x03_\x00\x00\x00\x00\x00\x00\x00\x00"
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Deleting key "\x00\x00\x00\x00\x00\x00\x00\x03_\x00\x00\x00\x00\x00\x00\x00\x00" successfully
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Deleting key "\x00\x00\x00\x00\x00\x00\x00\x04_\x00\x00\x00\x00\x00\x00\x00\x00"
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Deleting key "\x00\x00\x00\x00\x00\x00\x00\x04_\x00\x00\x00\x00\x00\x00\x00\x00" successfully
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Putting key "finishedCompactRev"
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Putting key "finishedCompactRev" successfully
    logger.go:130: 2026-04-03T11:27:17.685Z	DEBUG	bbolt	Committing transaction 4
    logger.go:130: 2026-04-03T11:27:17.686Z	DEBUG	bbolt	Committing transaction 4 successfully
    logger.go:130: 2026-04-03T11:27:17.686Z	INFO	finished scheduled compaction	{"compact-revision": 5, "took": "620.078µs", "hash": 3662656987, "current-db-size-bytes": 20480, "current-db-size": "20 kB", "current-db-size-in-use-bytes": 16384, "current-db-size-in-use": "16 kB"}
    logger.go:130: 2026-04-03T11:27:17.686Z	INFO	storing new hash	{"hash": 3662656987, "revision": 5, "compact-revision": -1}
    watch_compaction_loss_bug_test.go:126: watcher 1 (startRev=1): expected CompactRevision=5 but never received — silently advanced past compaction point
    watch_compaction_loss_bug_test.go:126: watcher 2 (startRev=1): expected CompactRevision=5 but never received — silently advanced past compaction point
    watch_compaction_loss_bug_test.go:126: watcher 3 (startRev=1): expected CompactRevision=5 but never received — silently advanced past compaction point
    watch_compaction_loss_bug_test.go:128: FAIL: 3 watcher(s) never received compaction notification — watch event loss after compaction
--- FAIL: TestWatchNoEventLossOnCompactBug (0.16s)
FAIL
FAIL	go.etcd.io/etcd/server/v3/storage/mvcc	0.179s
FAIL
```
