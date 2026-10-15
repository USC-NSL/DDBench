# Code Investigation

## What was searched
The symptom describes a leader transfer ending in a failed or incorrect election when a membership change is in progress at the time of the transfer, while elections triggered by election timeout behave normally. Read how a transferee reacts to `MsgTimeoutNow` in `src/raft.rs` and the `campaign()` it starts.

## What was found
```
$ grep -n "MsgTimeoutNow" src/raft.rs
1159:                    "{} sent MsgTimeoutNow to {} after received MsgAppResp",
1280:                "{} sends MsgTimeoutNow to {} immediately as {} already has up-to-date log",
1572:            MessageType::MsgTimeoutNow => debug!(
1573:                "{} [term {} state {:?}] ignored MsgTimeoutNow from {}",
1623:            MessageType::MsgTimeoutNow => {
1626:                        "{} [term {}] received MsgTimeoutNow from {} and starts an election to \
1638:                        "{} received MsgTimeoutNow from {} but is not promotable",
2016:        let msg = new_message(to, MessageType::MsgTimeoutNow, None);
```

```
$ cat -n src/raft.rs | sed -n '1600,1643p'
  1600	                self.handle_append_entries(&m);
  1601	            }
  1602	            MessageType::MsgHeartbeat => {
  1603	                self.election_elapsed = 0;
  1604	                self.leader_id = m.get_from();
  1605	                self.handle_heartbeat(m);
  1606	            }
  1607	            MessageType::MsgSnapshot => {
  1608	                self.election_elapsed = 0;
  1609	                self.leader_id = m.get_from();
  1610	                self.handle_snapshot(m);
  1611	            }
  1612	            MessageType::MsgTransferLeader => {
  1613	                if self.leader_id == INVALID_ID {
  1614	                    info!(
  1615	                        "{} no leader at term {}; dropping leader transfer msg",
  1616	                        self.tag, self.term
  1617	                    );
  1618	                    return Ok(());
  1619	                }
  1620	                m.set_to(self.leader_id);
  1621	                self.send(m);
  1622	            }
  1623	            MessageType::MsgTimeoutNow => {
  1624	                if self.promotable() {
  1625	                    info!(
  1626	                        "{} [term {}] received MsgTimeoutNow from {} and starts an election to \
  1627	                         get leadership.",
  1628	                        self.tag,
  1629	                        self.term,
  1630	                        m.get_from()
  1631	                    );
  1632	                    // Leadership transfers never use pre-vote even if self.pre_vote is true; we
  1633	                    // know we are not recovering from a partition so there is no need for the
  1634	                    // extra round trip.
  1635	                    self.campaign(CAMPAIGN_TRANSFER);
  1636	                } else {
  1637	                    info!(
  1638	                        "{} received MsgTimeoutNow from {} but is not promotable",
  1639	                        self.tag,
  1640	                        m.get_from()
  1641	                    );
  1642	                }
  1643	            }
```

```
$ cat -n src/raft.rs | sed -n '799,847p'
   799	    ///
   800	    /// If prevote is enabled, this is handled as well.
   801	    pub fn campaign(&mut self, campaign_type: &[u8]) {
   802	        let (vote_msg, term) = if campaign_type == CAMPAIGN_PRE_ELECTION {
   803	            self.become_pre_candidate();
   804	            // Pre-vote RPCs are sent for next term before we've incremented self.term.
   805	            (MessageType::MsgRequestPreVote, self.term + 1)
   806	        } else {
   807	            self.become_candidate();
   808	            (MessageType::MsgRequestVote, self.term)
   809	        };
   810	        let self_id = self.id;
   811	        if self.quorum() == self.poll(self_id, vote_resp_msg_type(vote_msg), true) {
   812	            // We won the election after voting for ourselves (which must mean that
   813	            // this is a single-node cluster). Advance to the next state.
   814	            if campaign_type == CAMPAIGN_PRE_ELECTION {
   815	                self.campaign(CAMPAIGN_ELECTION);
   816	            } else {
   817	                self.become_leader();
   818	            }
   819	            return;
   820	        }
   821	
   822	        // Only send vote request to voters.
   823	        let prs = self.take_prs();
   824	        prs.voters()
   825	            .keys()
   826	            .filter(|&id| *id != self_id)
   827	            .for_each(|&id| {
   828	                info!(
   829	                    "{} [logterm: {}, index: {}] sent {:?} request to {} at term {}",
   830	                    self.tag,
   831	                    self.raft_log.last_term(),
   832	                    self.raft_log.last_index(),
   833	                    vote_msg,
   834	                    id,
   835	                    self.term
   836	                );
   837	                let mut m = new_message(id, vote_msg, None);
   838	                m.set_term(term);
   839	                m.set_index(self.raft_log.last_index());
   840	                m.set_log_term(self.raft_log.last_term());
   841	                if campaign_type == CAMPAIGN_TRANSFER {
   842	                    m.set_context(campaign_type.to_vec());
   843	                }
   844	                self.send(m);
   845	            });
   846	        self.set_prs(prs);
   847	    }
```

## Developer hypothesis
A transferee starts its election from the `MsgTimeoutNow` handler. Worth checking what that election depends on when a membership change is in progress at the same time.
