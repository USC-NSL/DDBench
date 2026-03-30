# Reproduce: ZooKeeper #4925

## Prerequisites

- Java 11 (JDK)
- Maven 3.8+
- Git

## Step 1: Clone and checkout

```bash
git clone https://github.com/apache/zookeeper.git
cd zookeeper
git checkout e5dd60bf0512ccc1e090d99410a8da48623219da~1
```

## Step 2: Build the project

```bash
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```

## Step 3: Inject and run the regression test

The test starts a 3-node ZK ensemble, creates data on the leader, shuts down followers at specific points, restarts them to trigger DIFF sync, and verifies data consistency.

```bash
# Copy QuorumSyncTest.java into the test source tree
cp QuorumSyncTest.java zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/

# Run the test
cd zookeeper-server
mvn test -Dtest="QuorumSyncTest#testStaleDiffSync" -DfailIfNoTests=false -q
```

## Expected result (bug present)

The test FAILS because after a stale follower rejoins via DIFF sync and later becomes leader, committed znodes are missing. The `assertNotNull(zk.exists(path, false))` assertion fails for znodes like `/foo0`, `/foo1`, etc.:

```
org.opentest4j.AssertionFailedError: path /foo0 not found ==> expected: not <null>
```
