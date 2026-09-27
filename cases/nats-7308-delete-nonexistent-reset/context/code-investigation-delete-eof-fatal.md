# Code Investigation

## What was searched
The symptom describes deleting a non-existent message (seq beyond stream's last seq) causing a full cluster state reset and stream inaccessibility. Investigated how `applyStreamEntries` handles `ErrStoreEOF` from a delete operation.

## What was found
```
$ sed -n "3052,3078p" server/jetstream_cluster.go   # deleteMsgOp in applyStreamEntries
			case deleteMsgOp:
				md, err := decodeMsgDelete(buf[1:])
				...
				var removed bool
				if md.NoErase {
					removed, err = mset.removeMsg(md.Seq)
				} else {
					removed, err = mset.eraseMsg(md.Seq)
				}

				// Cluster reset error.
				if err == ErrStoreEOF {
					return err
				}

$ sed -n "2465,2485p" server/jetstream_cluster.go   # caller
				if err := js.applyStreamEntries(mset, ce, isRecovering); err == nil {
					ne, nb = n.Applied(ce.Index)
					ce.ReturnToPool()
				} else {
					ce.ReturnToPool()
					...
					if isClusterResetErr(err) {
						...
						if mset.resetClusteredState(err) {
							aq.recycle(&ces)
							return
						}
					}
				}

$ sed -n "746,749p" server/store.go   # isClusterResetErr
func isClusterResetErr(err error) bool {
	return err == errLastSeqMismatch || err == ErrStoreEOF || err == errFirstSequenceMismatch || ...
}
```

The chain of events:
1. Client calls `DeleteMsg` with a sequence beyond the stream's last sequence
2. The delete is proposed to the Raft group and committed
3. In `applyStreamEntries`, `removeMsg(seq)` or `eraseMsg(seq)` returns `ErrStoreEOF` (seq is beyond EOF)
4. The `deleteMsgOp` handler immediately returns `ErrStoreEOF` as a fatal error (line 3072-3074)
5. The caller sees `isClusterResetErr(ErrStoreEOF) == true` and calls `resetClusteredState`
6. This resets the entire Raft group, triggering leader election and making the stream temporarily inaccessible

## Developer hypothesis
The `deleteMsgOp` handler's error return path in `applyStreamEntries` and the `isClusterResetErr` check that receives it.
