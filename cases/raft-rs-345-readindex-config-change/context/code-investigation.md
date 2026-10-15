# Code Investigation

## What was searched
The symptom describes a ReadIndex request that was pending on the leader when an unresponsive peer was removed: the read does not complete when the leader becomes the only voter, and only completes after roughly a heartbeat interval. Searched for how the leader tracks and completes pending read-only requests and read the node-removal path (`src/raft.rs`).

## What was found
```
$ grep -n "read_only" src/raft.rs
27:use super::read_only::{ReadOnly, ReadOnlyOption, ReadState};
153:    pub read_only: ReadOnly,
241:            read_only: ReadOnly::new(c.read_only_option),
328:        self.read_only.pending_read_count()
725:        let ctx = self.read_only.last_pending_request_ctx();
774:        self.read_only = ReadOnly::new(self.read_only.option);
1409:            if self.read_only.option != ReadOnlyOption::Safe || m.context.is_empty() {
1414:        match self.read_only.recv_ack(m) {
1419:        let rss = self.read_only.advance(m, &self.logger);
1647:                    match self.read_only.option {
1650:                            self.read_only
```

```
$ cat -n src/raft.rs | sed -n '1386,1438p'
  1386	    fn handle_heartbeat_response(
  1387	        &mut self,
  1388	        m: &Message,
  1389	        prs: &mut ProgressSet,
  1390	        ctx: &mut HandleResponseContext,
  1391	    ) {
  1392	        // Update the node. Drop the value explicitly since we'll check the qourum after.
  1393	        {
  1394	            let pr = prs.get_mut(m.from).unwrap();
  1395	            pr.recent_active = true;
  1396	            pr.resume();
  1397	
  1398	            // free one slot for the full inflights window to allow progress.
  1399	            if pr.state == ProgressState::Replicate && pr.ins.full() {
  1400	                pr.ins.free_first_one();
  1401	            }
  1402	            // Does it request snapshot?
  1403	            if pr.matched < self.raft_log.last_index()
  1404	                || pr.pending_request_snapshot != INVALID_INDEX
  1405	            {
  1406	                ctx.send_append = true;
  1407	            }
  1408	
  1409	            if self.read_only.option != ReadOnlyOption::Safe || m.context.is_empty() {
  1410	                return;
  1411	            }
  1412	        }
  1413	
  1414	        match self.read_only.recv_ack(m) {
  1415	            Some(acks) if prs.has_quorum(acks) => {}
  1416	            _ => return,
  1417	        }
  1418	
  1419	        let rss = self.read_only.advance(m, &self.logger);
  1420	        for rs in rss {
  1421	            let mut req = rs.req;
  1422	            if req.from == INVALID_ID || req.from == self.id {
  1423	                // from local member
  1424	                let rs = ReadState {
  1425	                    index: rs.index,
  1426	                    request_ctx: req.take_entries()[0].take_data(),
  1427	                };
  1428	                self.read_states.push(rs);
  1429	            } else {
  1430	                let mut to_send = Message::default();
  1431	                to_send.set_msg_type(MessageType::MsgReadIndexResp);
  1432	                to_send.to = req.from;
  1433	                to_send.index = rs.index;
  1434	                to_send.set_entries(req.take_entries());
  1435	                ctx.more_to_send.push(to_send);
  1436	            }
  1437	        }
  1438	    }
```

```
$ cat -n src/raft.rs | sed -n '2199,2223p'
  2199	    /// Removes a node from the raft.
  2200	    ///
  2201	    /// # Errors
  2202	    ///
  2203	    /// * `id` is not a voter or learner.
  2204	    pub fn remove_node(&mut self, id: u64) -> Result<()> {
  2205	        self.mut_prs().remove(id)?;
  2206	
  2207	        // do not try to commit or abort transferring if there are no voters in the cluster.
  2208	        if self.prs().voter_ids().is_empty() {
  2209	            return Ok(());
  2210	        }
  2211	
  2212	        // The quorum size is now smaller, so see if any pending entries can
  2213	        // be committed.
  2214	        if self.maybe_commit() {
  2215	            self.bcast_append();
  2216	        }
  2217	        // If the removed node is the lead_transferee, then abort the leadership transferring.
  2218	        if self.state == StateRole::Leader && self.lead_transferee == Some(id) {
  2219	            self.abort_leader_transfer();
  2220	        }
  2221	
  2222	        Ok(())
  2223	    }
```

## Developer hypothesis
Pending ReadIndex requests are tracked in `read_only` and completed as acknowledgements arrive. Worth checking how they make progress when the set of voters changes while they are pending.
