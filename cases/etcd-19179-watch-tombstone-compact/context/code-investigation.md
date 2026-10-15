# Code Investigation

## What was searched
The symptom describes a delete event no longer being delivered to watches after etcd restarts, when compaction had been run at the delete revision before the restart. Looked at how the in-memory key index is rebuilt from the backend on startup (`restoreIntoIndex` / `restoreChunk` in `server/storage/mvcc/kvstore.go`).

## What was found
```
$ cat -n server/storage/mvcc/kvstore.go | sed -n '426,500p'
   426	type revKeyValue struct {
   427		key  []byte
   428		kv   mvccpb.KeyValue
   429		kstr string
   430	}
   431	
   432	func restoreIntoIndex(lg *zap.Logger, idx index) (chan<- revKeyValue, <-chan int64) {
   433		rkvc, revc := make(chan revKeyValue, restoreChunkKeys), make(chan int64, 1)
   434		go func() {
   435			currentRev := int64(1)
   436			defer func() { revc <- currentRev }()
   437			// restore the tree index from streaming the unordered index.
   438			kiCache := make(map[string]*keyIndex, restoreChunkKeys)
   439			for rkv := range rkvc {
   440				ki, ok := kiCache[rkv.kstr]
   441				// purge kiCache if many keys but still missing in the cache
   442				if !ok && len(kiCache) >= restoreChunkKeys {
   443					i := 10
   444					for k := range kiCache {
   445						delete(kiCache, k)
   446						if i--; i == 0 {
   447							break
   448						}
   449					}
   450				}
   451				// cache miss, fetch from tree index if there
   452				if !ok {
   453					ki = &keyIndex{key: rkv.kv.Key}
   454					if idxKey := idx.KeyIndex(ki); idxKey != nil {
   455						kiCache[rkv.kstr], ki = idxKey, idxKey
   456						ok = true
   457					}
   458				}
   459	
   460				rev := BytesToRev(rkv.key)
   461				verify.Verify(func() {
   462					if rev.Main < currentRev {
   463						panic(fmt.Errorf("revision %d shouldn't be less than the previous revision %d", rev.Main, currentRev))
   464					}
   465				})
   466				currentRev = rev.Main
   467	
   468				if ok {
   469					if isTombstone(rkv.key) {
   470						if err := ki.tombstone(lg, rev.Main, rev.Sub); err != nil {
   471							lg.Warn("tombstone encountered error", zap.Error(err))
   472						}
   473						continue
   474					}
   475					ki.put(lg, rev.Main, rev.Sub)
   476				} else if !isTombstone(rkv.key) {
   477					ki.restore(lg, Revision{Main: rkv.kv.CreateRevision}, rev, rkv.kv.Version)
   478					idx.Insert(ki)
   479					kiCache[rkv.kstr] = ki
   480				}
   481			}
   482		}()
   483		return rkvc, revc
   484	}
   485	
   486	func restoreChunk(lg *zap.Logger, kvc chan<- revKeyValue, keys, vals [][]byte, keyToLease map[string]lease.LeaseID) {
   487		for i, key := range keys {
   488			rkv := revKeyValue{key: key}
   489			if err := rkv.kv.Unmarshal(vals[i]); err != nil {
   490				lg.Fatal("failed to unmarshal mvccpb.KeyValue", zap.Error(err))
   491			}
   492			rkv.kstr = string(rkv.kv.Key)
   493			if isTombstone(key) {
   494				delete(keyToLease, rkv.kstr)
   495			} else if lid := lease.LeaseID(rkv.kv.Lease); lid != lease.NoLease {
   496				keyToLease[rkv.kstr] = lid
   497			} else {
   498				delete(keyToLease, rkv.kstr)
   499			}
   500			kvc <- rkv
```

## Developer hypothesis
The index rebuild in `restoreIntoIndex()` branches on whether a key is already indexed and on the kind of revision being replayed. Worth checking how that branching covers the on-disk state that compaction can leave behind for a key.
