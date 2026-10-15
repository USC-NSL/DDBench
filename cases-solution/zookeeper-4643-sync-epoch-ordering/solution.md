# Solution: ZooKeeper #4643

- **Issue:** https://issues.apache.org/jira/browse/ZOOKEEPER-4643
- **Fix commit:** [`9fcb805fa1bb37b1f64ceb3bc5d7ccf349971bb7`](https://github.com/apache/zookeeper/commit/9fcb805fa1bb37b1f64ceb3bc5d7ccf349971bb7)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/apache/zookeeper/pull/2152
- **Commit:** `9fcb805fa1bb37b1f64ceb3bc5d7ccf349971bb7`

## Fix locus
- **Component:** ZAB synchronization / leader-follower sync protocol
- **Files:**
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java`
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java`
  - `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java`
  - `zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java`

## Root cause

In `Learner.syncWithLeader()`, when processing the NEWLEADER packet during the synchronization phase, the follower performed operations in the wrong order:

1. **Buggy order:** `startupWithoutServing()` → process ALL proposals (committed AND uncommitted) → `commit()` → `setCurrentEpoch()` → `ACK`
2. **Correct order:** Process only COMMITTED proposals → `commit()` → `setCurrentEpoch()` → `startupWithoutServing()` → `ACK`

The buggy code called `zk.startupWithoutServing()` before persisting committed transactions, which started the `SyncRequestProcessor` and `CommitProcessor` prematurely. It also processed ALL proposals in `packetsNotCommitted` regardless of whether they had corresponding COMMITs in `packetsCommitted`. This meant uncommitted proposals were persisted to disk.

## Diagnosis chain

1. **Runtime evidence:** After a sequence of leader elections and follower restarts, committed znodes disappear. The data loss is silent — no crash or error log directly points to the cause.

2. **Narrowing the subsystem:** The symptom occurs specifically during follower synchronization after a leader change. The ZAB sync phase (`Learner.syncWithLeader()`) is responsible for bringing followers up to date.

3. **Code reasoning:** Reading `syncWithLeader()`, one discovers that `setCurrentEpoch()` (which writes to `currentEpoch` file on disk) is called after processing proposals, but the ordering between `commit()` (persisting to txn log) and `setCurrentEpoch()` is wrong. If a crash happens between epoch update and transaction persistence, the follower will have a higher epoch but stale history.

4. **Confirmation:** The fix reorders the operations: persist committed transactions first, then update epoch, then start serving. It also ensures only proposals with corresponding COMMITs (in `packetsCommitted`) are processed during NEWLEADER.

## Fix description

The fix restructures the NEWLEADER handling in `syncWithLeader()`:

1. Instead of processing ALL proposals from `packetsNotCommitted`, only process those with matching entries in `packetsCommitted` (i.e., actually committed proposals)
2. Call `processTxn()` alongside `appendRequest()` to update in-memory state correctly
3. Call `commit()` to persist transactions to disk BEFORE updating `currentEpoch`
4. Move `startupWithoutServing()` to after the epoch update, so processors don't start prematurely
5. Leave outstanding (uncommitted) proposals in `packetsNotCommitted` for later processing after UPTODATE

## How to apply

```bash
git checkout 9fcb805fa1bb37b1f64ceb3bc5d7ccf349971bb7
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```
