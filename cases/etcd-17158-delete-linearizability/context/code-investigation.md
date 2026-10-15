# Code Investigation

## What was searched
The symptom describes a read issued right after a successful delete still returning the old value, with the stale read disappearing on its own after a short interval. Looked at how the storage backend makes writes from the current (not yet committed) batch transaction visible to readers in `server/storage/backend/batch_tx.go`.

## What was found
```
$ grep -n "^func" server/storage/backend/batch_tx.go
80:func (t *batchTx) Lock() {
85:func (t *batchTx) lock() {
89:func (t *batchTx) LockInsideApply() {
102:func (t *batchTx) LockOutsideApply() {
107:func (t *batchTx) Unlock() {
114:func (t *batchTx) UnsafeCreateBucket(bucket Bucket) {
126:func (t *batchTx) UnsafeDeleteBucket(bucket Bucket) {
139:func (t *batchTx) UnsafePut(bucket Bucket, key []byte, value []byte) {
144:func (t *batchTx) UnsafeSeqPut(bucket Bucket, key []byte, value []byte) {
148:func (t *batchTx) unsafePut(bucketType Bucket, key []byte, value []byte, seq bool) {
173:func (t *batchTx) UnsafeRange(bucketType Bucket, key, endKey []byte, limit int64) ([][]byte, [][]byte) {
185:func unsafeRange(c *bolt.Cursor, key, endKey []byte, limit int64) (keys [][]byte, vs [][]byte) {
208:func (t *batchTx) UnsafeDelete(bucketType Bucket, key []byte) {
229:func (t *batchTx) UnsafeForEach(bucket Bucket, visitor func(k, v []byte) error) error {
233:func unsafeForEach(tx *bolt.Tx, bucket Bucket, visitor func(k, v []byte) error) error {
241:func (t *batchTx) Commit() {
248:func (t *batchTx) CommitAndStop() {
254:func (t *batchTx) safePending() int {
260:func (t *batchTx) commit(stop bool) {
294:func newBatchTxBuffered(backend *backend) *batchTxBuffered {
306:func (t *batchTxBuffered) Unlock() {
320:func (t *batchTxBuffered) Commit() {
326:func (t *batchTxBuffered) CommitAndStop() {
332:func (t *batchTxBuffered) commit(stop bool) {
339:func (t *batchTxBuffered) unsafeCommit(stop bool) {
365:func (t *batchTxBuffered) UnsafePut(bucket Bucket, key []byte, value []byte) {
370:func (t *batchTxBuffered) UnsafeSeqPut(bucket Bucket, key []byte, value []byte) {
```

```
$ sed -n '289,373p' server/storage/backend/batch_tx.go
type batchTxBuffered struct {
	batchTx
	buf txWriteBuffer
}

func newBatchTxBuffered(backend *backend) *batchTxBuffered {
	tx := &batchTxBuffered{
		batchTx: batchTx{backend: backend},
		buf: txWriteBuffer{
			txBuffer:   txBuffer{make(map[BucketID]*bucketBuffer)},
			bucket2seq: make(map[BucketID]bool),
		},
	}
	tx.Commit()
	return tx
}

func (t *batchTxBuffered) Unlock() {
	if t.pending != 0 {
		t.backend.readTx.Lock() // blocks txReadBuffer for writing.
		// gofail: var beforeWritebackBuf struct{}
		t.buf.writeback(&t.backend.readTx.buf)
		// gofail: var afterWritebackBuf struct{}
		t.backend.readTx.Unlock()
		if t.pending >= t.backend.batchLimit {
			t.commit(false)
		}
	}
	t.batchTx.Unlock()
}

func (t *batchTxBuffered) Commit() {
	t.lock()
	t.commit(false)
	t.Unlock()
}

func (t *batchTxBuffered) CommitAndStop() {
	t.lock()
	t.commit(true)
	t.Unlock()
}

func (t *batchTxBuffered) commit(stop bool) {
	// all read txs must be closed to acquire boltdb commit rwlock
	t.backend.readTx.Lock()
	t.unsafeCommit(stop)
	t.backend.readTx.Unlock()
}

func (t *batchTxBuffered) unsafeCommit(stop bool) {
	if t.backend.hooks != nil {
		// gofail: var commitBeforePreCommitHook struct{}
		t.backend.hooks.OnPreCommitUnsafe(t)
		// gofail: var commitAfterPreCommitHook struct{}
	}

	if t.backend.readTx.tx != nil {
		// wait all store read transactions using the current boltdb tx to finish,
		// then close the boltdb tx
		go func(tx *bolt.Tx, wg *sync.WaitGroup) {
			wg.Wait()
			if err := tx.Rollback(); err != nil {
				t.backend.lg.Fatal("failed to rollback tx", zap.Error(err))
			}
		}(t.backend.readTx.tx, t.backend.readTx.txWg)
		t.backend.readTx.reset()
	}

	t.batchTx.commit(stop)

	if !stop {
		t.backend.readTx.tx = t.backend.begin(false)
	}
}

func (t *batchTxBuffered) UnsafePut(bucket Bucket, key []byte, value []byte) {
	t.batchTx.UnsafePut(bucket, key, value)
	t.buf.put(bucket, key, value)
}

func (t *batchTxBuffered) UnsafeSeqPut(bucket Bucket, key []byte, value []byte) {
	t.batchTx.UnsafeSeqPut(bucket, key, value)
	t.buf.putSeq(bucket, key, value)
}
```

## Developer hypothesis
Readers see a combination of the committed bolt state and a write buffer that the buffered batch transaction writes back on `Unlock()`. The short-lived nature of the stale read suggests checking how the backend keeps that buffer and the bolt transaction in agreement between commits.
