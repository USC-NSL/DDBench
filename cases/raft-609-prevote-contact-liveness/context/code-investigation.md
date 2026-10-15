# Code Investigation

## What was searched
The symptom describes followers that never become candidates after the leader stops sending heartbeats, as long as another node keeps sending them pre-vote requests. Read the follower-side pre-vote RPC handler (`requestPreVote` in `raft.go`).

## What was found
```
$ cat -n raft.go | sed -n '1735,1809p'
  1735	// requestPreVote is invoked when we get a request Pre-Vote RPC call.
  1736	func (r *Raft) requestPreVote(rpc RPC, req *RequestPreVoteRequest) {
  1737		defer metrics.MeasureSince([]string{"raft", "rpc", "requestVote"}, time.Now())
  1738		r.observe(*req)
  1739	
  1740		// Setup a response
  1741		resp := &RequestPreVoteResponse{
  1742			RPCHeader: r.getRPCHeader(),
  1743			Term:      r.getCurrentTerm(),
  1744			Granted:   false,
  1745		}
  1746		var rpcErr error
  1747		defer func() {
  1748			rpc.Respond(resp, rpcErr)
  1749		}()
  1750	
  1751		// Check if we have an existing leader [who's not the candidate] and also
  1752		candidate := r.trans.DecodePeer(req.GetRPCHeader().Addr)
  1753		candidateID := ServerID(req.ID)
  1754	
  1755		// if the Servers list is empty that mean the cluster is very likely trying to bootstrap,
  1756		// Grant the vote
  1757		if len(r.configurations.latest.Servers) > 0 && !inConfiguration(r.configurations.latest, candidateID) {
  1758			r.logger.Warn("rejecting pre-vote request since node is not in configuration",
  1759				"from", candidate)
  1760			return
  1761		}
  1762	
  1763		if leaderAddr, leaderID := r.LeaderWithID(); leaderAddr != "" && leaderAddr != candidate {
  1764			r.logger.Warn("rejecting pre-vote request since we have a leader",
  1765				"from", candidate,
  1766				"leader", leaderAddr,
  1767				"leader-id", string(leaderID))
  1768			return
  1769		}
  1770	
  1771		// Ignore an older term
  1772		if req.Term < r.getCurrentTerm() {
  1773			return
  1774		}
  1775	
  1776		if req.Term > r.getCurrentTerm() {
  1777			// continue processing here to possibly grant the pre-vote as in a "real" vote this will transition us to follower
  1778			r.logger.Debug("received a requestPreVote with a newer term, grant the pre-vote")
  1779			resp.Term = req.Term
  1780		}
  1781	
  1782		// if we get a request for a pre-vote from a nonVoter  and the request term is higher, do not grant the Pre-Vote
  1783		// This could happen when a node, previously voter, is converted to non-voter
  1784		if len(r.configurations.latest.Servers) > 0 && !hasVote(r.configurations.latest, candidateID) {
  1785			r.logger.Warn("rejecting pre-vote request since node is not a voter", "from", candidate)
  1786			return
  1787		}
  1788	
  1789		// Reject if their term is older
  1790		lastIdx, lastTerm := r.getLastEntry()
  1791		if lastTerm > req.LastLogTerm {
  1792			r.logger.Warn("rejecting pre-vote request since our last term is greater",
  1793				"candidate", candidate,
  1794				"last-term", lastTerm,
  1795				"last-candidate-term", req.LastLogTerm)
  1796			return
  1797		}
  1798	
  1799		if lastTerm == req.LastLogTerm && lastIdx > req.LastLogIndex {
  1800			r.logger.Warn("rejecting pre-vote request since our last index is greater",
  1801				"candidate", candidate,
  1802				"last-index", lastIdx,
  1803				"last-candidate-index", req.LastLogIndex)
  1804			return
  1805		}
  1806	
  1807		resp.Granted = true
  1808		r.setLastContact()
  1809	}
```

## Developer hypothesis
Worth checking how handling a steady stream of pre-vote requests interacts with a follower's own detection that the leader has gone away.
