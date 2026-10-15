# Code Investigation

## What was searched
The symptom describes a watcher whose start revision is below the compaction revision never receiving the compaction notification when the watch stream is slow to drain. Read how unsynced watchers are processed in `syncWatchers()` and how compacted watchers are picked out in `watcherGroup.choose()` / `chooseAll()`.

## What was found
```
$ cat -n server/storage/mvcc/watchable_store.go | sed -n '332,414p'
   332	// syncWatchers syncs unsynced watchers by:
   333	//  1. choose a set of watchers from the unsynced watcher group
   334	//  2. iterate over the set to get the minimum revision and remove compacted watchers
   335	//  3. use minimum revision to get all key-value pairs and send those events to watchers
   336	//  4. remove synced watchers in set from unsynced group and move to synced group
   337	func (s *watchableStore) syncWatchers() int {
   338		s.mu.Lock()
   339		defer s.mu.Unlock()
   340	
   341		if s.unsynced.size() == 0 {
   342			return 0
   343		}
   344	
   345		s.store.revMu.RLock()
   346		defer s.store.revMu.RUnlock()
   347	
   348		// in order to find key-value pairs from unsynced watchers, we need to
   349		// find min revision index, and these revisions can be used to
   350		// query the backend store of key-value pairs
   351		curRev := s.store.currentRev
   352		compactionRev := s.store.compactMainRev
   353	
   354		wg, minRev := s.unsynced.choose(maxWatchersPerSync, curRev, compactionRev)
   355		minBytes, maxBytes := NewRevBytes(), NewRevBytes()
   356		minBytes = RevToBytes(Revision{Main: minRev}, minBytes)
   357		maxBytes = RevToBytes(Revision{Main: curRev + 1}, maxBytes)
   358	
   359		// UnsafeRange returns keys and values. And in boltdb, keys are revisions.
   360		// values are actual key-value pairs in backend.
   361		tx := s.store.b.ReadTx()
   362		tx.RLock()
   363		revs, vs := tx.UnsafeRange(schema.Key, minBytes, maxBytes, 0)
   364		evs := kvsToEvents(s.store.lg, wg, revs, vs)
   365		// Must unlock after kvsToEvents, because vs (come from boltdb memory) is not deep copy.
   366		// We can only unlock after Unmarshal, which will do deep copy.
   367		// Otherwise we will trigger SIGSEGV during boltdb re-mmap.
   368		tx.RUnlock()
   369	
   370		victims := make(watcherBatch)
   371		wb := newWatcherBatch(wg, evs)
   372		for w := range wg.watchers {
   373			w.minRev = curRev + 1
   374	
   375			eb, ok := wb[w]
   376			if !ok {
   377				// bring un-notified watcher to synced
   378				s.synced.add(w)
   379				s.unsynced.delete(w)
   380				continue
   381			}
   382	
   383			if eb.moreRev != 0 {
   384				w.minRev = eb.moreRev
   385			}
   386	
   387			if w.send(WatchResponse{WatchID: w.id, Events: eb.evs, Revision: curRev}) {
   388				pendingEventsGauge.Add(float64(len(eb.evs)))
   389			} else {
   390				w.victim = true
   391			}
   392	
   393			if w.victim {
   394				victims[w] = eb
   395			} else {
   396				if eb.moreRev != 0 {
   397					// stay unsynced; more to read
   398					continue
   399				}
   400				s.synced.add(w)
   401			}
   402			s.unsynced.delete(w)
   403		}
   404		s.addVictim(victims)
   405	
   406		vsz := 0
   407		for _, v := range s.victims {
   408			vsz += len(v)
   409		}
   410		slowWatcherGauge.Set(float64(s.unsynced.size() + vsz))
   411	
   412		return s.unsynced.size()
   413	}
   414	
```

```
$ cat -n server/storage/mvcc/watcher_group.go | sed -n '222,266p'
   222	
   223	// choose selects watchers from the watcher group to update
   224	func (wg *watcherGroup) choose(maxWatchers int, curRev, compactRev int64) (*watcherGroup, int64) {
   225		if len(wg.watchers) < maxWatchers {
   226			return wg, wg.chooseAll(curRev, compactRev)
   227		}
   228		ret := newWatcherGroup()
   229		for w := range wg.watchers {
   230			if maxWatchers <= 0 {
   231				break
   232			}
   233			maxWatchers--
   234			ret.add(w)
   235		}
   236		return &ret, ret.chooseAll(curRev, compactRev)
   237	}
   238	
   239	func (wg *watcherGroup) chooseAll(curRev, compactRev int64) int64 {
   240		minRev := int64(math.MaxInt64)
   241		for w := range wg.watchers {
   242			if w.minRev > curRev {
   243				// after network partition, possibly choosing future revision watcher from restore operation
   244				// with watch key "proxy-namespace__lostleader" and revision "math.MaxInt64 - 2"
   245				// do not panic when such watcher had been moved from "synced" watcher during restore operation
   246				if !w.restore {
   247					panic(fmt.Errorf("watcher minimum revision %d should not exceed current revision %d", w.minRev, curRev))
   248				}
   249	
   250				// mark 'restore' done, since it's chosen
   251				w.restore = false
   252			}
   253			if w.minRev < compactRev {
   254				select {
   255				case w.ch <- WatchResponse{WatchID: w.id, CompactRevision: compactRev}:
   256					w.compacted = true
   257					wg.delete(w)
   258				default:
   259					// retry next time
   260				}
   261				continue
   262			}
   263			if minRev > w.minRev {
   264				minRev = w.minRev
   265			}
   266		}
```

## Developer hypothesis
The compaction-notification path in `chooseAll()` and the watcher-processing loop in `syncWatchers()` both run on every sync pass. Worth checking how they cooperate when a watcher's channel is full.
