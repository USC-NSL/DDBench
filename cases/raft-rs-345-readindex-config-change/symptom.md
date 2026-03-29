# Symptom

After a configuration change that removes a node from the Raft cluster (shrinking the quorum), pending ReadIndex requests stall indefinitely until the next heartbeat round.

## Observable behavior
- A ReadIndex request is sent to the leader of a 2-node cluster.
- Heartbeats are broadcast but the response from one peer is lost or delayed.
- The peer is removed via `remove_node`, shrinking quorum from 2 to 1.
- Despite the leader's self-ack now being sufficient for the new quorum, `read_states` remains empty.
- The read only completes after the next full heartbeat round, causing unnecessary latency.

## Root mechanism
- `remove_node` does not re-evaluate pending ReadIndex requests against the new (smaller) quorum.
- The leader already has its own ack recorded in `ReadOnly.pending_read_index`, but this is never checked again after the quorum threshold changes.
