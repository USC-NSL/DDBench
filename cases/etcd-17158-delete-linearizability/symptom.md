# Symptom

After deleting a key in etcd's backend storage, subsequent reads may still return the deleted key's value. This violates linearizability: a client that successfully deletes a key can immediately read it back as if the delete never happened.

## Observable behavior

- A key is written to the backend via `UnsafePut` and the transaction is committed, persisting the key-value pair to bbolt and the read buffer.
- The key is then deleted via `UnsafeDelete`. The delete modifies the pending bbolt transaction but does NOT update the in-memory read buffer.
- When `Unlock()` is called on the batch transaction, the buffer (which still contains the put entry) is written back to the read transaction buffer. Because `pending < batchLimit`, the bbolt transaction is not committed.
- A subsequent read via `ReadTx.UnsafeRange` checks the read buffer first and finds the stale key-value pair. It returns the deleted key as if it still exists.
- `BatchTx.UnsafeRange` correctly reports the key as deleted (it checks the pending bbolt transaction directly), creating an inconsistency between the two read paths.
- In a running etcd cluster, this manifests as deleted users still being authenticatable, removed cluster members still appearing in membership queries, or deleted keys returning stale values -- until the next periodic bbolt commit flushes the pending delete.
