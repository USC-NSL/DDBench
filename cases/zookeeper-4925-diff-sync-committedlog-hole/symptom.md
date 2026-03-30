# Symptom

After a stale follower rejoins the ensemble via DIFF sync, it has a hole in its `committedLog` in-memory data structure. If this follower later becomes leader, the hole propagates to other stale nodes via DIFF sync, causing silent data loss.

## Observable behavior

- A stale follower (one that was offline while the leader committed transactions) rejoins via DIFF sync
- After DIFF sync completes, the follower's in-memory `committedLog` has a gap: some committed transactions are missing from the middle of the log
- When this follower is later elected leader, it serves DIFF sync to other stale followers using its own `committedLog`, which has the same hole
- Committed transactions silently disappear from the ensemble — znodes that were successfully created and acknowledged are not found
- The bug is a regression introduced by the ZOOKEEPER-4394 fix, which changed `processTxn` to use a variant that does not populate `committedLog` during the SYNCHRONIZATION phase
- Only affects ZooKeeper version 3.9.3 and later

## Impact

- Data loss: committed transactions are missing from the leader's `committedLog`
- The loss is silent — no crash, no error log, no exception
- Clients observe missing znodes or stale data when reading from affected nodes
- The issue compounds with multiple leader elections as holes propagate across nodes
