# Symptom

In a raft-rs cluster, a leader transfer can result in a failed or incorrect election when cluster membership is changing at the time of the transfer.

## Observable behavior

- A leader transfer is initiated while a configuration change (e.g., removing a node) is in progress.
- The transfer target node starts an election but either fails to win or wins with an incorrect quorum, leading to repeated election rounds or potential split-brain.
- The issue does not occur during normal elections triggered by election timeout -- only during explicit leader transfers.
- In production, this manifests as leadership transfer instability when cluster membership changes coincide with leader transfers.
