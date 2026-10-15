# Reproduce: ZooKeeper #4643

## Prerequisites

- Docker. The JDK and Maven are in the `bug-bench/zookeeper` image.

## Step 1: Set up the case and open a shell

```bash
# from the repository root
./bench.sh setup zookeeper-4643-sync-epoch-ordering   # case repository at the buggy commit, built
./bench.sh shell zookeeper-4643-sync-epoch-ordering   # source at /workspace/src
```

Run the remaining steps inside the shell, from `/workspace/src`.

## Step 2: Build the project

```bash
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```

## Step 3: Inject and run the regression test

The test simulates a leader-follower ZAB conversation where the leader sends SNAP + outstanding PROPOSAL + NEWLEADER to a follower. It verifies that only committed transactions are persisted before the epoch is updated.

```bash
cd /workspace/src/zookeeper-server
mvn test -Dtest="Zab1_0Test#testNormalFollowerRun_ProcessCommitInSyncAfterAckNewLeader"
```

## Expected result (bug present)

The test FAILS because the buggy code persists all proposals (including uncommitted ones) to disk during NEWLEADER processing, before updating the epoch. The assertion checking that only committed data is on disk will fail:
```
org.opentest4j.AssertionFailedError: expected: <19791209299968> (firstZxid) but was: <19791210301440> (proposalZxid)
```

## Oracle verdict

`./bench.sh reproduce zookeeper-4643-sync-epoch-ordering` rebuilds the worktree and runs the oracle (`reproduce.sh`). It injects its own test class, `DDBenchOracleSyncEpochTest#testOnlyCommittedTxnsPersistedBeforeEpochUpdate` (built on `Zab1_0Test`'s follower conversation), in which a scripted leader sends SNAP, one uncommitted PROPOSAL and NEWLEADER, then COMMIT and UPTODATE.

- **FAIL** (exit 1): after the follower acknowledges NEWLEADER, its last processed zxid, or the zxid reloaded from its data directory, is the uncommitted proposal's instead of the committed one; any other assertion of the conversation (epochs, a snapshot taken during NEWLEADER, the proposal applied within 10 s and persisted after COMMIT) also fails it. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): until COMMIT arrives the follower has applied and persisted only the committed transaction, and after COMMIT and UPTODATE it applies and persists the proposal.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or `zookeeper-server` is missing), or the test produced no JUnit report and no compilation error explains it.
