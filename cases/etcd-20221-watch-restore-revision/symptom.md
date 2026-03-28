# Symptom

After a follower receives and applies a snapshot from the leader, existing watches may receive events with revisions earlier than their originally requested starting point.

## Observable behavior
- A client creates a watch on a key with a future start revision (e.g., revision 100).
- A snapshot restore occurs on the server (as happens when a follower catches up via snapshot transfer from the leader).
- After the restore, the watch begins receiving events whose revisions are well below the requested start revision.
- This violates the watch API contract: a watch created with a start revision should never deliver events with revisions lower than that start revision.
