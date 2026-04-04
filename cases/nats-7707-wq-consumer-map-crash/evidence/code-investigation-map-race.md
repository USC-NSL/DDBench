# Code Investigation

## What was searched
The symptom describes a fatal `concurrent map iteration and map write` crash during concurrent consumer create/delete on a WorkQueue stream. Investigated locking around `mset.consumers` map access in the consumer creation path.

## What was found
```
$ sed -n "1032,1048p" server/consumer.go   # consumer update path (existing consumer found)
		if eo, ok := mset.consumers[cName]; ok {
			mset.mu.Unlock()                            // <--- lock released here (line 1033)
			if action == ActionCreate {
				ocfg := eo.config()
				copyConsumerMetadata(config, &ocfg)
				if !reflect.DeepEqual(config, &ocfg) {
					return nil, NewJSConsumerAlreadyExistsError()
				}
			}
			// Check for overlapping subjects if we are a workqueue
			if cfg.Retention == WorkQueuePolicy {
				subjects := gatherSubjectFilters(config.FilterSubject, config.FilterSubjects)
				if !mset.partitionUnique(cName, subjects) {   // <--- iterates map without lock (line 1044)
					return nil, NewJSConsumerWQConsumerNotUniqueError()
				}
			}

$ cat server/stream.go (line 7476)   # partitionUnique iterates mset.consumers
func (mset *stream) partitionUnique(name string, partitions []string) bool {
	for _, partition := range partitions {
		for n, o := range mset.consumers {    // <--- iterating the map
			if n == name {
				continue
			}
			...
		}
	}
	return true
}

$ cat server/stream.go (line 7345)   # removeConsumer deletes from map (caller holds lock)
// Lock should be held.
func (mset *stream) removeConsumer(o *consumer) {
	...
	if mset.consumers != nil {
		delete(mset.consumers, o.name)    // <--- writing to the map
```

Note that `partitionUnique` iterates `mset.consumers` after the lock has been released, while `removeConsumer` deletes from the same map and expects the lock to be held by its caller.

## Developer hypothesis
The locking discipline around `mset.consumers` in the consumer update path and `partitionUnique`.
