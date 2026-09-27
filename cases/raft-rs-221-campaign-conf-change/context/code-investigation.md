# Code Investigation

## What was searched
The symptom describes leader transfer failing when a configuration change is in progress. Investigated how `MsgHup` and `MsgTimeoutNow` handle pending configuration changes differently.

## What was found

### MsgHup handler (src/raft.rs:1005-1031) — checks pending conf changes
```rust
MessageType::MsgHup => if self.state != StateRole::Leader {
    let ents = self
        .raft_log
        .slice(
            self.raft_log.applied + 1,
            self.raft_log.committed + 1,
            raft_log::NO_LIMIT,
        ).expect("unexpected error getting unapplied entries");
    let n = self.num_pending_conf(&ents);
    if n != 0 && self.raft_log.committed > self.raft_log.applied {
        warn!(
            "{} cannot campaign at term {} since there are still {} pending \
             configuration changes to apply",
            self.tag, self.term, n
        );
        return Ok(());
    }
    // ... proceeds to campaign
```

### MsgTimeoutNow handler (src/raft.rs:1623-1635) — no conf change check
```rust
MessageType::MsgTimeoutNow => {
    if self.promotable() {
        info!(
            "{} [term {}] received MsgTimeoutNow from {} and starts an election to \
             get leadership.",
            self.tag,
            self.term,
            m.get_from()
        );
        // Leadership transfers never use pre-vote even if self.pre_vote is true; we
        // know we are not recovering from a partition so there is no need for the
        // extra round trip.
        self.campaign(CAMPAIGN_TRANSFER);
    }
```

### num_pending_conf (src/raft.rs:792)
```
$ grep -n "num_pending_conf" src/raft.rs
792:    fn num_pending_conf(&self, ents: &[Entry]) -> usize {
1013:                let n = self.num_pending_conf(&ents);
```

## Developer hypothesis
The `campaign()` call site in the `MsgTimeoutNow` handler compared to the `MsgHup` handler.
