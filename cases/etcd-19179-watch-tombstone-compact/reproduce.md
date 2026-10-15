# Reproduce: etcd #19179

## Step 1: Inject and run the regression test

The bug is in the mvcc (multi-version concurrency control) layer's restore path. It can be reproduced with a unit test that exercises the KV store directly, without needing a full etcd cluster.

```bash
cd /workspace/src
go test -v -run "^TestRestoreTombstoneAfterCompaction$" -count=1 -timeout 120s ./server/storage/mvcc/
```

The test does the following:
1. Creates a store and puts several keys (foo1 through foo5).
2. Deletes foo1 (creating a tombstone at revision 7).
3. Compacts at revision 7, removing all prior put revisions for foo1 but keeping the tombstone.
4. Verifies foo1 has a key index entry (the tombstone) before close.
5. Closes the store and reopens it from the same backend (triggering restore via `restoreIntoIndex`).
6. Checks whether the key index contains an entry for foo1 after restore.

## Expected result (bug present)

The test fails because after restore, foo1 has no key index entry. The `restoreIntoIndex` function skips tombstones that are the only remaining revision for a key, so the tombstone is never reconstructed.

```
Bug present — foo1 has NO key index entry after restore. The tombstone at rev 7 was not
reconstructed during restoreIntoIndex. If compaction resumes after a crash, this tombstone
will be permanently deleted from the database, causing the delete event to be lost on watches.
```

## Oracle verdict

`./bench.sh reproduce etcd-19179-watch-tombstone-compact` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `foo1`–`foo5` are put, `foo1` is deleted (revision 7), the store is compacted at revision 7, closed, and reopened from the same backend, the key index has no entry for `foo1`. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): `foo1` still has a key-index entry after the store is reopened.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or the etcd source is missing), or Go module downloads fail so the oracle test cannot run.
