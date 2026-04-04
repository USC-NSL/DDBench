# Code Investigation

## What was searched
The symptom describes followers being unable to start elections despite the leader being unreachable, when pre-vote requests are being received. Investigated the `requestPreVote` handler to understand how it interacts with the election timer.

## What was found
```
$ sed -n "1735,1815p" raft.go

// requestPreVote is invoked when we get a request Pre-Vote RPC call.
func (r *Raft) requestPreVote(rpc RPC, req *RequestPreVoteRequest) {
	defer metrics.MeasureSince([]string{"raft", "rpc", "requestVote"}, time.Now())
	r.observe(*req)

	// Setup a response
	resp := &RequestPreVoteResponse{
		RPCHeader: r.getRPCHeader(),
		Term:      r.getCurrentTerm(),
		Granted:   false,
	}
	...

	if leaderAddr, leaderID := r.LeaderWithID(); leaderAddr != "" && leaderAddr != candidate {
		r.logger.Warn("rejecting pre-vote request since we have a leader",
			"from", candidate,
			"leader", leaderAddr,
			"leader-id", string(leaderID))
		return
	}

	// Ignore an older term
	if req.Term < r.getCurrentTerm() {
		return
	}

	if req.Term > r.getCurrentTerm() {
		r.logger.Debug("received a requestPreVote with a newer term, grant the pre-vote")
		resp.Term = req.Term
	}
	...

	resp.Granted = true
	r.setLastContact()  // <-- line 1808
}
```

Also confirmed `setLastContact` resets the election timer:
```
$ grep -n "setLastContact" raft.go

510:	r.setLastContact()
1579:	r.setLastContact()
1732:	r.setLastContact()
1808:	r.setLastContact()
1953:	r.setLastContact()
1956:// setLastContact is used to set the last contact time to now
1957:func (r *Raft) setLastContact() {
```

## Developer hypothesis
The `setLastContact()` call in the `requestPreVote` handler and its effect on the election timer.
