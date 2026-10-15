# Code Investigation

## What was searched
The symptom describes the log store reporting an invalid-argument error during the log cleanup that follows a snapshot, on a node that had earlier received a snapshot from the leader. Searched for where Raft deletes log ranges and read the post-snapshot compaction routine (`compactLogs` in `snapshot.go`).

## What was found
```
$ grep -n "compactLogs\|DeleteRange" *.go | grep -v _test.go
api.go:378:	if err := logs.DeleteRange(firstLogIndex, lastLogIndex); err != nil {
inmem_store.go:78:// DeleteRange implements the LogStore interface.
inmem_store.go:79:func (i *InmemStore) DeleteRange(min, max uint64) error {
log.go:85:	// DeleteRange deletes a range of log entries. The range is inclusive.
log.go:86:	DeleteRange(min, max uint64) error
log_cache.go:72:func (c *LogCache) DeleteRange(min, max uint64) error {
log_cache.go:78:	return c.store.DeleteRange(min, max)
raft.go:1303:				if err := r.logs.DeleteRange(entry.Index, lastLogIdx); err != nil {
raft.go:1591:	if err := r.compactLogs(req.LastLogIndex); err != nil {
snapshot.go:201:	if err := r.compactLogs(snapReq.index); err != nil {
snapshot.go:209:// compactLogs takes the last inclusive index of a snapshot
snapshot.go:211:func (r *Raft) compactLogs(snapIdx uint64) error {
snapshot.go:212:	defer metrics.MeasureSince([]string{"raft", "compactLogs"}, time.Now())
snapshot.go:234:	if err := r.logs.DeleteRange(minLog, maxLog); err != nil {
```

```
$ cat -n snapshot.go | sed -n '209,238p'
   209	// compactLogs takes the last inclusive index of a snapshot
   210	// and trims the logs that are no longer needed.
   211	func (r *Raft) compactLogs(snapIdx uint64) error {
   212		defer metrics.MeasureSince([]string{"raft", "compactLogs"}, time.Now())
   213		// Determine log ranges to compact
   214		minLog, err := r.logs.FirstIndex()
   215		if err != nil {
   216			return fmt.Errorf("failed to get first log index: %v", err)
   217		}
   218	
   219		// Check if we have enough logs to truncate
   220		lastLogIdx, _ := r.getLastLog()
   221		if lastLogIdx <= r.conf.TrailingLogs {
   222			return nil
   223		}
   224	
   225		// Truncate up to the end of the snapshot, or `TrailingLogs`
   226		// back from the head, which ever is further back. This ensures
   227		// at least `TrailingLogs` entries, but does not allow logs
   228		// after the snapshot to be removed.
   229		maxLog := min(snapIdx, lastLogIdx-r.conf.TrailingLogs)
   230	
   231		r.logger.Info("compacting logs", "from", minLog, "to", maxLog)
   232	
   233		// Compact the logs
   234		if err := r.logs.DeleteRange(minLog, maxLog); err != nil {
   235			return fmt.Errorf("log compaction failed: %v", err)
   236		}
   237		return nil
   238	}
```

## Developer hypothesis
`compactLogs()` derives what to delete from the current state of the log store and the snapshot being taken. Worth checking which assumptions about the log store it makes, and whether they still hold on a node that earlier installed a snapshot received from the leader.
