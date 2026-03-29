# Reproduce: raft-rs #345

## Step 1: Build the test harness
```bash
cd harness
cargo test --no-run
```

## Step 2: Inject and run the regression test
The `reproduce.sh` script appends a test function `test_read_when_quorum_becomes_less_bug` to `harness/tests/integration_cases/test_raft.rs`. This test:

1. Creates a 2-node Raft cluster and elects node 1 as leader.
2. Sends a ReadIndex request to the leader.
3. Broadcasts heartbeats but drops the heartbeat response from node 2.
4. Removes node 2 via `remove_node(2)`, shrinking quorum from 2 to 1.
5. Asserts that `read_states` is non-empty (the read should complete with the leader's self-ack).

```bash
cd harness
cargo test test_read_when_quorum_becomes_less_bug -- --nocapture
```

## Expected result (bug present)
The assertion `!network.peers[&1].read_states.is_empty()` fails because pending reads are not re-evaluated when the quorum shrinks.
