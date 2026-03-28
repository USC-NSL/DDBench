# Symptom

During leadership transfer in a multi-node Raft cluster under write load, the leader continues accepting and committing write operations in a brief window after the transfer has been initiated. This causes the transfer target to lose the subsequent election because its log falls behind, resulting in intermittent transfer failures.

## Observable behavior
- A 7-node Raft cluster is running with continuous `Apply()` write load from multiple client goroutines.
- A leadership transfer is initiated via `LeadershipTransferToServer()` targeting a specific follower. The transfer future returns without error, indicating the signal was sent successfully.
- Immediately after the transfer future returns, write operations submitted to the current leader still succeed (return nil error) instead of being rejected. These writes advance the leader's committed log index.
- The transfer target starts its election but sometimes fails to gather a majority of votes. Other followers have already received the leader's recent writes and reject the target's vote request because its log is not as up-to-date.
- As a result, a different node may win the election, or the transfer times out entirely. The designated target does not become leader.
- The failure rate correlates directly with write throughput: under heavy write load, more writes land during the transfer window, increasing the log gap and the probability of transfer failure. Without concurrent writes, transfers succeed reliably.
- Cluster logs show the leader processing new log entries and replicating them to followers between the transfer initiation and the target's election attempt.
