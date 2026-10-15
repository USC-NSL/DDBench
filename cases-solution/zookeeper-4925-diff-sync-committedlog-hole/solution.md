# Solution: ZooKeeper #4925

- **Issue:** https://issues.apache.org/jira/browse/ZOOKEEPER-4925
- **Fix commit:** [`e5dd60bf0512ccc1e090d99410a8da48623219da`](https://github.com/apache/zookeeper/commit/e5dd60bf0512ccc1e090d99410a8da48623219da)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/apache/zookeeper/pull/2254
- **Commit:** `e5dd60bf0512ccc1e090d99410a8da48623219da`

## Fix locus
- **Component:** ZAB synchronization / leader-follower sync protocol
- **Files:**
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java`
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java`
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java`
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java`
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Follower.java`
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/TxnLogEntry.java`
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/Request.java`

## Root cause

The ZOOKEEPER-4394 fix introduced a regression by changing `Learner.syncWithLeader()` to use `processTxn(TxnHeader, Record)` instead of `processTxn(Request)`. The two-argument variant does not add transactions to the in-memory `committedLog` data structure during the SYNCHRONIZATION phase.

When a stale follower rejoins via DIFF sync:
1. The follower receives committed transactions from the leader
2. These transactions are applied to the data tree via `processTxn(TxnHeader, Record)`
3. However, this variant does NOT call `ZKDatabase.addCommittedProposal()`, so the transactions are missing from `committedLog`
4. The follower's `committedLog` now has a hole — transactions exist in the data tree but not in `committedLog`

When this follower later becomes leader:
1. Other stale followers request DIFF sync
2. The new leader serves DIFFs from its `committedLog`
3. Since `committedLog` has holes, some committed transactions are not sent to the stale followers
4. The result is silent data loss across the ensemble

## Diagnosis chain

1. **Runtime evidence:** After a stale follower rejoins and later becomes leader, clients observe missing znodes. Committed data that was successfully created and acknowledged is no longer found.

2. **Narrowing the subsystem:** The symptom occurs specifically when a stale follower syncs via DIFF and then becomes leader. The ZAB sync phase (`Learner.syncWithLeader()`) and the `committedLog` data structure are the relevant components.

3. **Code reasoning:** Reading the DIFF sync path in `syncWithLeader()`, one discovers that `processTxn(TxnHeader, Record)` is called during SYNCHRONIZATION. Unlike `processTxn(Request)`, this variant does not invoke `addCommittedProposal()`, leaving `committedLog` incomplete.

4. **Confirmation:** The fix removes the two-argument `processTxn` variant and ensures `processTxn(Request)` is used, which properly maintains `committedLog` by calling `addCommittedProposal()`.

## Fix description

The fix restores proper `committedLog` maintenance during SYNCHRONIZATION:

1. Removes the `processTxn(TxnHeader, Record)` variant that bypassed `committedLog` population
2. Uses `processTxn(Request)` which properly calls `ZKDatabase.addCommittedProposal()` for every committed transaction
3. Ensures that during DIFF sync, all received transactions are added to `committedLog`
4. When a follower becomes leader, its `committedLog` is complete and can serve accurate DIFFs to other stale nodes

## How to apply

```bash
git checkout e5dd60bf0512ccc1e090d99410a8da48623219da
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```
