# Code Investigation

## What was searched
The symptom describes a `WARNING: DATA RACE` between a goroutine performing candidate operations and a goroutine handling AppendEntries (heartbeat) requests while leadership transfers are triggered repeatedly. Looked at how heartbeats are dispatched to the Raft node and at the code they reach, alongside the start of the candidate loop (`runCandidate`).

## What was found
```
$ grep -n "processHeartbeat\|SetHeartbeatHandler" *.go | grep -v _test.go
api.go:598:	trans.SetHeartbeatHandler(r.processHeartbeat)
inmem_transport.go:72:// SetHeartbeatHandler is used to set optional fast-path for
inmem_transport.go:74:func (i *InmemTransport) SetHeartbeatHandler(cb func(RPC)) {
net_transport.go:287:// SetHeartbeatHandler is used to set up a heartbeat handler
net_transport.go:290:func (n *NetworkTransport) SetHeartbeatHandler(cb func(rpc RPC)) {
raft.go:1346:// processHeartbeat is a special handler used just for heartbeat requests
raft.go:1349:func (r *Raft) processHeartbeat(rpc RPC) {
raft.go:1350:	defer metrics.MeasureSince([]string{"raft", "rpc", "processHeartbeat"}, time.Now())
transport.go:59:	// SetHeartbeatHandler is used to setup a heartbeat handler
transport.go:63:	SetHeartbeatHandler(cb func(rpc RPC))
```

```
$ cat -n raft.go | sed -n '281,300p'
   281	
   282	// runCandidate runs the main loop while in the candidate state.
   283	func (r *Raft) runCandidate() {
   284		term := r.getCurrentTerm() + 1
   285		r.logger.Info("entering candidate state", "node", r, "term", term)
   286		metrics.IncrCounter([]string{"raft", "state", "candidate"}, 1)
   287	
   288		// Start vote for us, and set a timeout
   289		voteCh := r.electSelf()
   290	
   291		// Make sure the leadership transfer flag is reset after each run. Having this
   292		// flag will set the field LeadershipTransfer in a RequestVoteRequst to true,
   293		// which will make other servers vote even though they have a leader already.
   294		// It is important to reset that flag, because this priviledge could be abused
   295		// otherwise.
   296		defer func() { r.candidateFromLeadershipTransfer = false }()
   297	
   298		electionTimeout := r.config().ElectionTimeout
   299		electionTimer := randomTimeout(electionTimeout)
   300	
```

```
$ cat -n raft.go | sed -n '1345,1410p'
  1345	
  1346	// processHeartbeat is a special handler used just for heartbeat requests
  1347	// so that they can be fast-pathed if a transport supports it. This must only
  1348	// be called from the main thread.
  1349	func (r *Raft) processHeartbeat(rpc RPC) {
  1350		defer metrics.MeasureSince([]string{"raft", "rpc", "processHeartbeat"}, time.Now())
  1351	
  1352		// Check if we are shutdown, just ignore the RPC
  1353		select {
  1354		case <-r.shutdownCh:
  1355			return
  1356		default:
  1357		}
  1358	
  1359		// Ensure we are only handling a heartbeat
  1360		switch cmd := rpc.Command.(type) {
  1361		case *AppendEntriesRequest:
  1362			r.appendEntries(rpc, cmd)
  1363		default:
  1364			r.logger.Error("expected heartbeat, got", "command", hclog.Fmt("%#v", rpc.Command))
  1365			rpc.Respond(nil, fmt.Errorf("unexpected command"))
  1366		}
  1367	}
  1368	
  1369	// appendEntries is invoked when we get an append entries RPC call. This must
  1370	// only be called from the main thread.
  1371	func (r *Raft) appendEntries(rpc RPC, a *AppendEntriesRequest) {
  1372		defer metrics.MeasureSince([]string{"raft", "rpc", "appendEntries"}, time.Now())
  1373		// Setup a response
  1374		resp := &AppendEntriesResponse{
  1375			RPCHeader:      r.getRPCHeader(),
  1376			Term:           r.getCurrentTerm(),
  1377			LastLog:        r.getLastIndex(),
  1378			Success:        false,
  1379			NoRetryBackoff: false,
  1380		}
  1381		var rpcErr error
  1382		defer func() {
  1383			rpc.Respond(resp, rpcErr)
  1384		}()
  1385	
  1386		// Ignore an older term
  1387		if a.Term < r.getCurrentTerm() {
  1388			return
  1389		}
  1390	
  1391		// Increase the term if we see a newer one, also transition to follower
  1392		// if we ever get an appendEntries call
  1393		if a.Term > r.getCurrentTerm() || (r.getState() != Follower && !r.candidateFromLeadershipTransfer) {
  1394			// Ensure transition to follower
  1395			r.setState(Follower)
  1396			r.setCurrentTerm(a.Term)
  1397			resp.Term = a.Term
  1398		}
  1399	
  1400		// Save the current leader
  1401		if len(a.Addr) > 0 {
  1402			r.setLeader(r.trans.DecodePeer(a.Addr), ServerID(a.ID))
  1403		} else {
  1404			r.setLeader(r.trans.DecodePeer(a.Leader), ServerID(a.ID))
  1405		}
  1406		// Verify the last log entry
  1407		if a.PrevLogEntry > 0 {
  1408			lastIdx, lastTerm := r.getLastEntry()
  1409	
  1410			var prevLogTerm uint64
```

## Developer hypothesis
Heartbeats can be handled through a separate fast path from the main RPC loop, and both that path and the candidate loop touch Raft state. Worth checking which goroutines read and write the state that the candidate loop and the AppendEntries handling share during a leadership transfer.
