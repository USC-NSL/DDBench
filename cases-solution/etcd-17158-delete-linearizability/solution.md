# Solution: etcd #17158

## Fix
- **PR:** https://github.com/etcd-io/etcd/pull/17195
- **Commit:** `b3bf59a3557ce81fb9d4615df667b4cacc6a4f6d`

## Fix locus
- **Component:** Backend storage / buffered batch transaction
- **Files:** `server/storage/backend/batch_tx.go`

## Root cause
In `server/storage/backend/batch_tx.go`, the `batchTxBuffered` type wraps bbolt transactions with an in-memory write buffer. `UnsafePut` and `UnsafeSeqPut` are overridden to write to both bbolt and the buffer. However, `UnsafeDelete` and `UnsafeDeleteBucket` are NOT overridden -- they fall through to the embedded `batchTx` methods, which only modify the pending bbolt transaction.

When `batchTxBuffered.Unlock()` is called after a delete:
1. The buffer (still containing the stale put entry) is written back to the read transaction buffer via `t.buf.writeback(&t.backend.readTx.buf)`.
2. The check `if t.pending >= t.backend.batchLimit` evaluates to false (because the batch limit is large), so the bbolt transaction is NOT committed.
3. A subsequent read via `ReadTx.UnsafeRange` checks the read buffer first, finds the stale key-value pair, and returns it as if the delete never happened.
4. `BatchTx.UnsafeRange` correctly reports the key as deleted because it reads from the pending bbolt transaction directly.

This creates a linearizability violation: `ReadTx` and `BatchTx` return different results for the same key after a delete. In a running etcd cluster, this manifests as deleted users still being authenticatable, removed cluster members still appearing in membership queries, or deleted keys returning stale values.

## Fix description
The fix adds two changes to `batchTxBuffered`:

1. **Override `UnsafeDelete` and `UnsafeDeleteBucket`** to track pending delete operations via a new `pendingDeleteOperations` counter:
```go
func (t *batchTxBuffered) UnsafeDelete(bucketType Bucket, key []byte) {
    t.batchTx.UnsafeDelete(bucketType, key)
    t.pendingDeleteOperations++
}

func (t *batchTxBuffered) UnsafeDeleteBucket(bucket Bucket) {
    t.batchTx.UnsafeDeleteBucket(bucket)
    t.pendingDeleteOperations++
}
```

2. **Force an immediate bbolt commit in `Unlock()`** when there are any pending delete operations:
```go
if t.pending >= t.backend.batchLimit || t.pendingDeleteOperations > 0 {
    t.commit(false)
}
```

The `pendingDeleteOperations` counter is reset to 0 in `unsafeCommit()` after the bbolt transaction is committed.

This ensures that after a delete, the bbolt transaction is committed before any subsequent reads, so the read path (which checks both bbolt and the buffer) no longer sees stale data.

## Diagnosis chain
1. **Runtime evidence:** After deleting a user, the user can still authenticate. After removing a cluster member, the member still appears in membership queries. These symptoms disappear after the next periodic bbolt commit (default batch interval), suggesting a timing-dependent buffering issue.
2. **Narrowing the component:** The backend storage layer (`server/storage/backend/`) implements a buffered batch transaction on top of bbolt. The `batchTxBuffered` type buffers writes and periodically commits to bbolt. The read path checks both the buffer and bbolt.
3. **Code-level reasoning:** `UnsafePut` is overridden in `batchTxBuffered` to update both bbolt and the buffer. `UnsafeDelete` is NOT overridden -- it only modifies bbolt. On `Unlock()`, the stale buffer is written back to the readTx, and if the batch limit hasn't been reached, bbolt isn't committed. This leaves the read path with stale data.

## Key files
- `server/storage/backend/batch_tx.go` (+34, -2) -- override `UnsafeDelete`/`UnsafeDeleteBucket` with pending counter, force commit on delete in `Unlock()`
- `server/storage/backend/batch_tx_test.go` (+89, -0) -- unit tests `TestRangeAfterDeleteMatch` and `TestRangeAfterDeleteBucketMatch`
- `tests/integration/clientv3/user_test.go` (+51, -0) -- integration test `TestAddUserAfterDelete`
- `tests/integration/member_test.go` (+31, -0) -- integration test `TestRemoveMember`

## How to apply
```bash
git checkout b3bf59a3557ce81fb9d4615df667b4cacc6a4f6d
make build
```
