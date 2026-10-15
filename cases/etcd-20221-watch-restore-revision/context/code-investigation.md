# Code Investigation

## What was searched
The symptom describes existing watches receiving events below their requested start revision after the server applies a snapshot from the leader. Looked at what the watchable store does with existing watchers on `Restore()` and how those watchers are then processed by `syncWatchers()` in `server/storage/mvcc/watchable_store.go`.

## What was found
```
$ cat -n server/storage/mvcc/watchable_store.go | sed -n '204,220p'
   204	func (s *watchableStore) Restore(b backend.Backend) error {
   205		s.mu.Lock()
   206		defer s.mu.Unlock()
   207		err := s.store.Restore(b)
   208		if err != nil {
   209			return err
   210		}
   211	
   212		for wa := range s.synced.watchers {
   213			wa.restore = true
   214			s.unsynced.add(wa)
   215		}
   216		s.synced = newWatcherGroup()
   217		return nil
   218	}
   219	
   220	// syncWatchersLoop syncs the watcher in the unsynced map every 100ms.
```

```
$ cat -n server/storage/mvcc/watchable_store.go | sed -n '340,413p'
   340	// syncWatchers syncs unsynced watchers by:
   341	//  1. choose a set of watchers from the unsynced watcher group
   342	//  2. iterate over the set to get the minimum revision and remove compacted watchers
   343	//  3. use minimum revision to get all key-value pairs and send those events to watchers
   344	//  4. remove synced watchers in set from unsynced group and move to synced group
   345	func (s *watchableStore) syncWatchers(evs []mvccpb.Event) (int, []mvccpb.Event) {
   346		s.mu.Lock()
   347		defer s.mu.Unlock()
   348	
   349		if s.unsynced.size() == 0 {
   350			return 0, []mvccpb.Event{}
   351		}
   352	
   353		s.store.revMu.RLock()
   354		defer s.store.revMu.RUnlock()
   355	
   356		// in order to find key-value pairs from unsynced watchers, we need to
   357		// find min revision index, and these revisions can be used to
   358		// query the backend store of key-value pairs
   359		curRev := s.store.currentRev
   360		compactionRev := s.store.compactMainRev
   361	
   362		wg, minRev := s.unsynced.choose(maxWatchersPerSync, curRev, compactionRev)
   363		evs = rangeEventsWithReuse(s.store.lg, s.store.b, evs, minRev, curRev+1)
   364	
   365		victims := make(watcherBatch)
   366		wb := newWatcherBatch(wg, evs)
   367		for w := range wg.watchers {
   368			if w.minRev < compactionRev {
   369				// Skip the watcher that failed to send compacted watch response due to w.ch is full.
   370				// Next retry of syncWatchers would try to resend the compacted watch response to w.ch
   371				continue
   372			}
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
   412		return s.unsynced.size(), evs
   413	}
```

## Developer hypothesis
On `Restore()`, previously synced watchers are flagged and moved back to the unsynced group, so they go through `syncWatchers()` again against the restored store. Worth checking how per-watcher revision state is handled during that re-sync.
