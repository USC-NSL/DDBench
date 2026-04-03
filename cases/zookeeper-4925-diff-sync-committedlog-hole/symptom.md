# Symptom

After a stale follower rejoins the ensemble and is later elected leader, committed data silently disappears from the cluster.

## Observable behavior

- A follower that was offline while the leader committed transactions rejoins and synchronizes with the leader.
- The synchronization appears to complete successfully with no errors.
- When this follower is later elected leader, other stale followers that synchronize with it end up missing some committed transactions.
- Committed znodes that were successfully created and acknowledged by clients are no longer found.
- The data loss is silent -- no crash, no error log, no exception.
- Clients observe missing znodes or stale data when reading from affected nodes.
- The issue compounds with multiple leader elections as the missing data propagates across nodes.

## Impact

- Silent data loss of committed transactions
- No crash or error to alert operators
- The problem worsens over time as more nodes are affected through subsequent leader elections
