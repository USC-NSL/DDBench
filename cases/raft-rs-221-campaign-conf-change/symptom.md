# Symptom

In a Raft cluster using leader transfer (`MsgTimeoutNow`), the transfer target node can start an election with a stale voter set when a configuration change has been committed but not yet applied.

## Observable behavior

- A leader transfer fails unexpectedly: the target node calls an election but does not win, or wins with incorrect quorum, leading to repeated election rounds or split-brain.
- The failure only occurs when a configuration change (e.g., `RemoveNode`) is committed to the Raft log but not yet applied to the state machine at the moment the leader transfer message arrives.
- The target node's election does not account for the pending configuration change, so it counts votes from nodes that should have been removed from the voter set. This can result in either election failure (insufficient votes) or a successful election with a stale configuration.
- Regular elections triggered by election timeout (`MsgHup`) correctly block while configuration changes are pending. Only the leader transfer path bypasses this check.
- In production, this manifests as leadership transfer instability when cluster membership changes coincide with leader transfers.
