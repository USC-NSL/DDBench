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
