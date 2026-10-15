# Code Investigation

## What was searched
The symptom describes reserved storage growing with each "Resetting stream cluster state" cycle until new streams are refused for exceeding resources. Read the clustered stream reset path (`resetClusteredState` in `server/jetstream_cluster.go`) and searched for where JetStream reserves and releases per-stream resources.

## What was found
```
$ cat -n server/jetstream_cluster.go | sed -n '2877,2960p'
  2877	// resetClusteredState is called when a clustered stream had an error (e.g sequence mismatch, bad snapshot) and needs to be reset.
  2878	func (mset *stream) resetClusteredState(err error) bool {
  2879		mset.mu.RLock()
  2880		s, js, jsa, sa, acc, node := mset.srv, mset.js, mset.jsa, mset.sa, mset.acc, mset.node
  2881		stype, isLeader, tierName, replicas := mset.cfg.Storage, mset.isLeader(), mset.tier, mset.cfg.Replicas
  2882		mset.mu.RUnlock()
  2883	
  2884		// Stepdown regardless if we are the leader here.
  2885		if isLeader && node != nil {
  2886			node.StepDown()
  2887		}
  2888	
  2889		// If we detect we are shutting down just return.
  2890		if js != nil && js.isShuttingDown() {
  2891			s.Debugf("Will not reset stream, JetStream shutting down")
  2892			return false
  2893		}
  2894	
  2895		// Server
  2896		if js.limitsExceeded(stype) {
  2897			s.Warnf("Will not reset stream, server resources exceeded")
  2898			return false
  2899		}
  2900	
  2901		// Account
  2902		if exceeded, _ := jsa.limitsExceeded(stype, tierName, replicas); exceeded {
  2903			s.Warnf("stream '%s > %s' errored, account resources exceeded", acc, mset.name())
  2904			return false
  2905		}
  2906	
  2907		if node != nil {
  2908			if errors.Is(err, errCatchupAbortedNoLeader) || err == errCatchupTooManyRetries {
  2909				// Don't delete all state, could've just been temporarily unable to reach the leader.
  2910				node.Stop()
  2911			} else {
  2912				// We delete our raft state. Will recreate.
  2913				node.Delete()
  2914			}
  2915		}
  2916	
  2917		// Preserve our current state and messages unless we have a first sequence mismatch.
  2918		shouldDelete := err == errFirstSequenceMismatch
  2919	
  2920		// Need to do the rest in a separate Go routine.
  2921		go func() {
  2922			mset.monitorWg.Wait()
  2923			mset.resetAndWaitOnConsumers()
  2924			// Stop our stream.
  2925			mset.stop(shouldDelete, false)
  2926	
  2927			if sa != nil {
  2928				js.mu.Lock()
  2929				if js.shuttingDown {
  2930					js.mu.Unlock()
  2931					return
  2932				}
  2933	
  2934				s.Warnf("Resetting stream cluster state for '%s > %s'", sa.Client.serviceAccount(), sa.Config.Name)
  2935				// Now wipe groups from assignments.
  2936				sa.Group.node = nil
  2937				var consumers []*consumerAssignment
  2938				if cc := js.cluster; cc != nil && cc.meta != nil {
  2939					ourID := cc.meta.ID()
  2940					for _, ca := range sa.consumers {
  2941						if rg := ca.Group; rg != nil && rg.isMember(ourID) {
  2942							rg.node = nil // Erase group raft/node state.
  2943							consumers = append(consumers, ca)
  2944						}
  2945					}
  2946				}
  2947				js.mu.Unlock()
  2948	
  2949				// This will reset the stream and consumers.
  2950				// Reset stream.
  2951				js.processClusterCreateStream(acc, sa)
  2952				// Reset consumers.
  2953				for _, ca := range consumers {
  2954					js.processClusterCreateConsumer(ca, nil, false)
  2955				}
  2956			}
  2957		}()
  2958	
  2959		return true
  2960	}
```

```
$ grep -n "reserveStreamResources\|releaseStreamResources" server/*.go | grep -v _test.go
server/jetstream.go:2478:func (js *jetStream) reserveStreamResources(cfg *StreamConfig) {
server/jetstream.go:2499:func (js *jetStream) releaseStreamResources(cfg *StreamConfig) {
server/stream.go:768:	mset.js.reserveStreamResources(&mset.cfg)
server/stream.go:2163:			js.reserveStreamResources(&StreamConfig{
server/stream.go:2169:			js.releaseStreamResources(&StreamConfig{
server/stream.go:5776:		js.releaseStreamResources(&mset.cfg)
```

## Developer hypothesis
A reset stops the stream and has it re-created from its assignment. Worth checking how JetStream's reserved-resource accounting is kept balanced across such a reset cycle.
