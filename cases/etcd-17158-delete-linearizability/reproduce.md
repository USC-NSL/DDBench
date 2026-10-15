# Reproduce: etcd #17158

## Step 1: Inject and run the regression test

The bug is in the backend storage layer's buffered batch transaction. It can be reproduced with a unit test in the `backend_test` package that exercises the `BatchTx` and `ReadTx` interfaces directly, without needing a full etcd cluster.

```bash
cd /workspace/src
go test -v -run "^TestRangeAfterDeleteMatch$" -count=1 -timeout 60s ./server/storage/backend/
```

The test does the following:
1. Creates a backend with a long batch interval (1 hour) and high batch limit (10000) so automatic commits never trigger during the test.
2. Puts a key ("foo" -> "bar") via `BatchTx.UnsafePut`, unlocks, and explicitly commits.
3. Verifies that both `BatchTx.UnsafeRange` and `ReadTx.UnsafeRange` return the key.
4. Deletes the key via `BatchTx.UnsafeDelete` and unlocks (no explicit commit).
5. Reads the key via both `BatchTx.UnsafeRange` and `ReadTx.UnsafeRange`, expecting both to return empty results.

## Expected result (bug present)

The test fails because `ReadTx.UnsafeRange` still returns the deleted key. The delete operation modified the pending bbolt transaction but did not update the read buffer. When `Unlock()` wrote the buffer back to the readTx, the stale put entry was copied, making the deleted key visible through the read path.

```
keys on read and batch transaction don't match after delete
  BatchTx returned: [] (correct -- key deleted)
  ReadTx returned:  [foo] (wrong -- stale buffer entry)
```

## Oracle verdict

`./bench.sh reproduce etcd-17158-delete-linearizability` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after a key is put and committed, then deleted through the batch transaction without a commit, a read through `ReadTx` still returns the deleted key, or `BatchTx` and `ReadTx` disagree on the bucket's contents (by range or by iteration). A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): after the delete, both `BatchTx` and `ReadTx` return no key, by range and by iteration.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or the etcd source is missing), or Go module downloads fail so the oracle test cannot run.
