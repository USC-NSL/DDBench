# Code Investigation

## What was searched
The symptom describes deleted keys returning stale values. A developer would investigate how writes and deletes propagate through the backend's buffered transaction layer, looking for asymmetry between put and delete operations.

## What was found

`batchTxBuffered` overrides `UnsafePut` to update the read buffer, but does NOT override `UnsafeDelete`:

```
$ grep -n "func.*batchTxBuffered" server/storage/backend/batch_tx.go
294:func newBatchTxBuffered(backend *backend) *batchTxBuffered {
306:func (t *batchTxBuffered) Unlock()
320:func (t *batchTxBuffered) Commit()
326:func (t *batchTxBuffered) CommitAndStop()
332:func (t *batchTxBuffered) commit(stop bool)
339:func (t *batchTxBuffered) unsafeCommit(stop bool)
365:func (t *batchTxBuffered) UnsafePut(bucket Bucket, key []byte, value []byte)
370:func (t *batchTxBuffered) UnsafeSeqPut(bucket Bucket, key []byte, value []byte)
```

The `UnsafePut` override writes to both the boltdb transaction AND the read buffer:

```go
// server/storage/backend/batch_tx.go:365-368
func (t *batchTxBuffered) UnsafePut(bucket Bucket, key []byte, value []byte) {
	t.batchTx.UnsafePut(bucket, key, value)
	t.buf.put(bucket, key, value)
}
```

But `UnsafeDelete` (inherited from `batchTx`) only writes to boltdb — it never touches the buffer:

```go
// server/storage/backend/batch_tx.go:208-225
func (t *batchTx) UnsafeDelete(bucketType Bucket, key []byte) {
	bucket := t.tx.Bucket(bucketType.Name())
	...
	err := bucket.Delete(key)
	...
	t.pending++
}
```

The `txWriteBuffer` type only has `put`/`putSeq` methods — no delete method exists:

```
$ grep -n "func.*txWriteBuffer" server/storage/backend/tx_buffer.go
49:func (txw *txWriteBuffer) put(bucket Bucket, k, v []byte)
55:func (txw *txWriteBuffer) putSeq(bucket Bucket, k, v []byte)
60:func (txw *txWriteBuffer) putInternal(bucket Bucket, k, v []byte)
71:func (txw *txWriteBuffer) reset()
```

## Developer hypothesis
The `batchTxBuffered` method set and the `txWriteBuffer` API surface, specifically the coverage of mutation types that flow through to the read buffer.
