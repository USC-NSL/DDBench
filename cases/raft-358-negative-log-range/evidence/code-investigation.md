# Code Investigation

## What was searched
The symptom describes a storage-layer error during post-snapshot log cleanup. Investigated the `compactLogs` function in `snapshot.go` to understand how log ranges are computed for deletion.

## What was found
```
$ grep -n "compactLogs\|DeleteRange\|minLog\|maxLog" snapshot.go

201:	if err := r.compactLogs(snapReq.index); err != nil {
209:// compactLogs takes the last inclusive index of a snapshot
211:func (r *Raft) compactLogs(snapIdx uint64) error {
214:	minLog, err := r.logs.FirstIndex()
229:	maxLog := min(snapIdx, lastLogIdx-r.conf.TrailingLogs)
231:	r.logger.Info("compacting logs", "from", minLog, "to", maxLog)
234:	if err := r.logs.DeleteRange(minLog, maxLog); err != nil {
```

Full function (snapshot.go:211-240):
```go
func (r *Raft) compactLogs(snapIdx uint64) error {
	defer metrics.MeasureSince([]string{"raft", "compactLogs"}, time.Now())
	// Determine log ranges to compact
	minLog, err := r.logs.FirstIndex()
	if err != nil {
		return fmt.Errorf("failed to get first log index: %v", err)
	}

	// Check if we have enough logs to truncate
	lastLogIdx, _ := r.getLastLog()
	if lastLogIdx <= r.conf.TrailingLogs {
		return nil
	}

	// Truncate up to the end of the snapshot, or `TrailingLogs`
	// back from the head, which ever is further back. This ensures
	// at least `TrailingLogs` entries, but does not allow logs
	// after the snapshot to be removed.
	maxLog := min(snapIdx, lastLogIdx-r.conf.TrailingLogs)

	r.logger.Info("compacting logs", "from", minLog, "to", maxLog)

	// Compact the logs
	if err := r.logs.DeleteRange(minLog, maxLog); err != nil {
		return fmt.Errorf("log compaction failed: %v", err)
	}
	return nil
}
```

## Developer hypothesis
The `compactLogs` function's computation of the range passed to `DeleteRange`.
