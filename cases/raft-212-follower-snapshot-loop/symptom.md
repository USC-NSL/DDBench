# Symptom: hashicorp/raft #212

When an out-of-date follower reconnects to the cluster after the leader has compacted its log, the follower gets stuck in an infinite snapshot install retry loop instead of successfully catching up.

The leader repeatedly attempts to install a snapshot on the follower, but the follower rejects the snapshot. The leader then retries, and the cycle continues indefinitely. The follower never successfully receives the snapshot and never catches up to the cluster.

In logs, you see repeated messages like:
```
[WARN] raft: Failed to install snapshot ... on ...
[INFO] raft: Installing snapshot ...
[WARN] raft: Failed to install snapshot ... on ...
```

This loop continues until the follower is manually restarted or the leader changes.
