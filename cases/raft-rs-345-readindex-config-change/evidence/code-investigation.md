# Code Investigation

## What was searched
The symptom describes a pending ReadIndex request not completing promptly after a node is removed, even though the leader is now the sole member. Investigated how `remove_node` interacts with pending ReadIndex requests.

## What was found

### remove_node (src/raft.rs:2204-2224)
```rust
pub fn remove_node(&mut self, id: u64) -> Result<()> {
    self.mut_prs().remove(id)?;

    // do not try to commit or abort transferring if there are no voters in the cluster.
    if self.prs().voter_ids().is_empty() {
        return Ok(());
    }

    // The quorum size is now smaller, so see if any pending entries can
    // be committed.
    if self.maybe_commit() {
        self.bcast_append();
    }
    // If the removed node is the lead_transferee, then abort the leadership transferring.
    if self.state == StateRole::Leader && self.lead_transferee == Some(id) {
        self.abort_leader_transfer();
    }

    Ok(())
}
```

### ReadIndex advance only happens on heartbeat response (src/raft.rs:1409-1419)
```rust
if self.read_only.option != ReadOnlyOption::Safe || m.context.is_empty() {
    return;
}

match self.read_only.recv_ack(m) {
    Some(acks) if prs.has_quorum(acks) => {}
    _ => return,
}

let rss = self.read_only.advance(m, &self.logger);
```

### ReadIndex request starts by broadcasting heartbeats (src/raft.rs:1647-1652)
```rust
match self.read_only.option {
    ReadOnlyOption::Safe => {
        let ctx = m.entries[0].data.to_vec();
        self.read_only
            .add_request(self.raft_log.committed, m, self.id);
        self.bcast_heartbeat_with_ctx(Some(ctx));
    }
```

## Developer hypothesis
The `remove_node` function's post-removal actions and the ReadIndex advancement path in `recv_ack` / `advance`.
