# Reproduce: ZooKeeper #4643

## Prerequisites

- Java 11 (JDK)
- Maven 3.8+
- Git

## Step 1: Clone and checkout

```bash
git clone https://github.com/apache/zookeeper.git
cd zookeeper
git checkout 9fcb805fa1bb37b1f64ceb3bc5d7ccf349971bb7~1
```

## Step 2: Build the project

```bash
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```

## Step 3: Inject and run the regression test

The test simulates a leader-follower ZAB conversation where the leader sends SNAP + outstanding PROPOSAL + NEWLEADER to a follower. It verifies that only committed transactions are persisted before the epoch is updated.

```bash
cd zookeeper-server
mvn test -Dtest="Zab1_0Test#testNormalFollowerRun_ProcessCommitInSyncAfterAckNewLeader"
```

## Expected result (bug present)

The test FAILS because the buggy code persists all proposals (including uncommitted ones) to disk during NEWLEADER processing, before updating the epoch. The assertion checking that only committed data is on disk will fail:
```
org.opentest4j.AssertionFailedError: expected: <19791209299968> (firstZxid) but was: <19791210301440> (proposalZxid)
```
