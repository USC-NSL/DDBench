# Reproduce: ZooKeeper #4925

## Prerequisites

- Docker. The JDK and Maven are in the `bug-bench/zookeeper` image.

## Step 1: Set up the case and open a shell

```bash
# from the repository root
./bench.sh setup zookeeper-4925-diff-sync-committedlog-hole   # case repository at the buggy commit, built
./bench.sh shell zookeeper-4925-diff-sync-committedlog-hole   # source at /workspace/src
```

Run the remaining steps inside the shell, from `/workspace/src`.

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
cd /workspace/src/zookeeper-server
mvn test -Dtest="QuorumSyncTest#testStaleDiffSync" -DfailIfNoTests=false -q
```

## Expected result (bug present)

The test FAILS because after a stale follower rejoins via DIFF sync and later becomes leader, committed znodes are missing. The `assertNotNull(zk.exists(path, false))` assertion fails for znodes like `/foo0`, `/foo1`, etc.:

```
org.opentest4j.AssertionFailedError: path /foo0 not found ==> expected: not <null>
```

## Oracle verdict

`./bench.sh reproduce zookeeper-4925-diff-sync-committedlog-hole` rebuilds the worktree and runs the oracle (`reproduce.sh`). It injects its own copy of the test, `DDBenchOracleQuorumSyncTest#testStaleDiffSync`: in a 3-server ensemble follower B is stopped, `/foo0`-`/foo9` are created, follower A is stopped, `/bar0`-`/bar9` are created and A is restarted; later the leader is stopped and B is restarted.

- **FAIL** (exit 1): any of the 20 znodes is missing when read through A after it rejoins, or through B after the leader is stopped. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): all 20 znodes are readable through both A and B.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or `zookeeper-server` is missing), or the test produced no JUnit report and no compilation error explains it.
