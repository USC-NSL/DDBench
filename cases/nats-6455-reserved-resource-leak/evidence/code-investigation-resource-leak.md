# Code Investigation

## What was searched
The symptom describes reserved disk usage growing over time during stream reset cycles until the server refuses new streams. Investigated how `resetClusteredState` handles resource accounting when stopping and re-creating a stream.

## What was found
```
$ sed -n "2877,2930p" server/jetstream_cluster.go   # resetClusteredState
func (mset *stream) resetClusteredState(err error) bool {
	...
	// Preserve our current state and messages unless we have a first sequence mismatch.
	shouldDelete := err == errFirstSequenceMismatch

	// Need to do the rest in a separate Go routine.
	go func() {
		mset.monitorWg.Wait()
		mset.resetAndWaitOnConsumers()
		// Stop our stream.
		mset.stop(shouldDelete, false)
		...

$ sed -n "5770,5790p" server/stream.go   # stop() resource release path
	if deleteFlag {
		if store != nil {
			// Ignore errors.
			store.Delete()
		}
		// Release any resources.
		js.releaseStreamResources(&mset.cfg)
		...
	} else if store != nil {
		// Ignore errors.
		store.Stop()
	}

$ sed -n "2499,2512p" server/jetstream.go   # releaseStreamResources
func (js *jetStream) releaseStreamResources(cfg *StreamConfig) {
	if cfg == nil || cfg.MaxBytes <= 0 {
		return
	}
	js.mu.Lock()
	switch cfg.Storage {
	case MemoryStorage:
		js.memReserved -= cfg.MaxBytes
	case FileStorage:
		js.storeReserved -= cfg.MaxBytes
	}
	...
}
```

The key issue: `resetClusteredState` sets `shouldDelete = (err == errFirstSequenceMismatch)`. For most reset-triggering errors (e.g., sequence mismatches from bad snapshots, catchup failures), `shouldDelete` is `false`. This calls `mset.stop(false, false)`.

In `stop()`, `releaseStreamResources` is only called when `deleteFlag` is true. When `deleteFlag` is false, the stream is stopped (store.Stop()) but the reserved resource counters (`js.storeReserved` / `js.memReserved`) are NOT decremented.

After `stop()`, `resetClusteredState` proceeds to re-add the stream assignment, which will reserve resources again — adding `MaxBytes` to the reserved counter a second time.

## Developer hypothesis
The `releaseStreamResources` call site in `stop()` and the `resetClusteredState` path that calls `stop()` and then re-adds the stream assignment.
