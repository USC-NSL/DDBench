# Symptom

A quorum queue member crashes after installing a Raft snapshot. The crash occurs when a slow or previously stopped follower restarts, installs a snapshot from the leader, and then attempts to deliver messages to consumers.

## Error signature

The crash manifests as a `badarg` error in a list operation called with lists of different lengths during effect handling after snapshot installation.

## Observable behavior

1. A follower that was stopped or running slowly restarts and installs a Raft snapshot from the leader.
2. Shortly after snapshot installation, the follower crashes with the error above.
3. The quorum queue member process crashes. It may recover by restarting, but the crash disrupts queue availability.

## Trigger conditions

- A 3-node quorum queue cluster
- A follower that is stopped or slow
- Messages are published and consumed while the follower is down
- A checkpoint is forced on the leader (truncating log entries)
- A consumer is attached to the follower's node while the follower is stopped
- The follower restarts and installs the snapshot
