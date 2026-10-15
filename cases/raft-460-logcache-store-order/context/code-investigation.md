# Code Investigation

## What was searched
The symptom describes a node that panics with "log not found" on restart after an earlier transient storage failure, and that seemed to keep operating normally in between. Raft can wrap its `LogStore` in an in-memory `LogCache`, so read how `LogCache` reads and writes entries (`log_cache.go`).

## What was found
```
$ cat -n log_cache.go
     1	package raft
     2	
     3	import (
     4		"fmt"
     5		"sync"
     6	)
     7	
     8	// LogCache wraps any LogStore implementation to provide an
     9	// in-memory ring buffer. This is used to cache access to
    10	// the recently written entries. For implementations that do not
    11	// cache themselves, this can provide a substantial boost by
    12	// avoiding disk I/O on recent entries.
    13	type LogCache struct {
    14		store LogStore
    15	
    16		cache []*Log
    17		l     sync.RWMutex
    18	}
    19	
    20	// NewLogCache is used to create a new LogCache with the
    21	// given capacity and backend store.
    22	func NewLogCache(capacity int, store LogStore) (*LogCache, error) {
    23		if capacity <= 0 {
    24			return nil, fmt.Errorf("capacity must be positive")
    25		}
    26		c := &LogCache{
    27			store: store,
    28			cache: make([]*Log, capacity),
    29		}
    30		return c, nil
    31	}
    32	
    33	func (c *LogCache) GetLog(idx uint64, log *Log) error {
    34		// Check the buffer for an entry
    35		c.l.RLock()
    36		cached := c.cache[idx%uint64(len(c.cache))]
    37		c.l.RUnlock()
    38	
    39		// Check if entry is valid
    40		if cached != nil && cached.Index == idx {
    41			*log = *cached
    42			return nil
    43		}
    44	
    45		// Forward request on cache miss
    46		return c.store.GetLog(idx, log)
    47	}
    48	
    49	func (c *LogCache) StoreLog(log *Log) error {
    50		return c.StoreLogs([]*Log{log})
    51	}
    52	
    53	func (c *LogCache) StoreLogs(logs []*Log) error {
    54		// Insert the logs into the ring buffer
    55		c.l.Lock()
    56		for _, l := range logs {
    57			c.cache[l.Index%uint64(len(c.cache))] = l
    58		}
    59		c.l.Unlock()
    60	
    61		return c.store.StoreLogs(logs)
    62	}
    63	
    64	func (c *LogCache) FirstIndex() (uint64, error) {
    65		return c.store.FirstIndex()
    66	}
    67	
    68	func (c *LogCache) LastIndex() (uint64, error) {
    69		return c.store.LastIndex()
    70	}
    71	
    72	func (c *LogCache) DeleteRange(min, max uint64) error {
    73		// Invalidate the cache on deletes
    74		c.l.Lock()
    75		c.cache = make([]*Log, len(c.cache))
    76		c.l.Unlock()
    77	
    78		return c.store.DeleteRange(min, max)
    79	}
```

## Developer hypothesis
`LogCache` serves recent entries from its ring buffer and forwards everything else to the wrapped `LogStore`. Worth checking how `LogCache` behaves when operations on the wrapped store fail.
