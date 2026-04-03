# Symptom

A raft cluster with pre-vote enabled becomes unable to elect a new leader when frequent pre-vote requests are being sent to followers.

## Observable behavior
- A 3-node raft cluster is running with pre-vote enabled (the default).
- The real leader stops sending heartbeats to followers (e.g., due to network partition or crash).
- A node (possibly the former leader or a misconfigured node with a low election timeout) continuously sends pre-vote requests to the followers.
- Despite the leader being unreachable, followers never transition to candidate state.
- The cluster remains leaderless indefinitely as long as the pre-vote spam continues.
- In production, this manifests as a liveness violation: the cluster is stuck without a leader, and all client writes fail with "no leader" errors.
