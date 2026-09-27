# Code Investigation

## What was searched
The symptom describes a node panicking with "log not found" after restart following a transient storage failure. Investigated the `LogCache.StoreLogs` method to understand the ordering of cache vs. backend writes.

## What was found
```
$ sed -n "40,65p" log_cache.go

func (c *LogCache) StoreLog(log *Log) error {
	return c.StoreLogs([]*Log{log})
}

func (c *LogCache) StoreLogs(logs []*Log) error {
	// Insert the logs into the ring buffer
	c.l.Lock()
	for _, l := range logs {
		c.cache[l.Index%uint64(len(c.cache))] = l
	}
	c.l.Unlock()

	return c.store.StoreLogs(logs)
}

func (c *LogCache) FirstIndex() (uint64, error) {
	return c.store.FirstIndex()
}

func (c *LogCache) LastIndex() (uint64, error) {
	return c.store.LastIndex()
}
```

Also confirmed the delegation pattern:
```
$ grep -n "StoreLogs\|store\.Store\|c\.store" log_cache.go

46:	return c.store.GetLog(idx, log)
50:	return c.StoreLogs([]*Log{log})
53:func (c *LogCache) StoreLogs(logs []*Log) error {
61:	return c.store.StoreLogs(logs)
65:	return c.store.FirstIndex()
69:	return c.store.LastIndex()
78:	return c.store.DeleteRange(min, max)
```

## Developer hypothesis
The ordering of cache writes and backend writes in `LogCache.StoreLogs`.
