# Reproduce: ZooKeeper #4846

## Prerequisites

- Docker. The JDK and Maven are in the `bug-bench/zookeeper` image.

## Step 1: Set up the case and open a shell

```bash
# from the repository root
./bench.sh setup zookeeper-4846-fuzzy-snapshot-acl   # case repository at the buggy commit, built
./bench.sh shell zookeeper-4846-fuzzy-snapshot-acl   # source at /workspace/src
```

Run the remaining steps inside the shell, from `/workspace/src`.

## Step 2: Build the project

```bash
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```

## Step 3: Inject and run the regression test

The test injects a method into `DataTreeTest.java` that simulates the fuzzy snapshot ACL race: it creates a node, removes the ACL from the cache, then attempts to re-create the same node (which throws NodeExistsException but should defensively fix the ACL), and finally creates a child node under the parent.

```bash
cd /workspace/src/zookeeper-server
mvn test -Dtest="DataTreeTest#testCreateNodeFixMissingACL" -DfailIfNoTests=false -q
```

## Expected result (bug present)

The test FAILS because creating the child node throws a `RuntimeException` -- the ACL reference for the parent node was removed from the cache during the simulated fuzzy snapshot race, and `createNode` does not defensively recover it. The stack trace references a missing ACL mapping in `ReferenceCountedACLCache`.

## Oracle verdict

`./bench.sh reproduce zookeeper-4846-fuzzy-snapshot-acl` rebuilds the worktree and runs the oracle (`reproduce.sh`). It injects its own test, `DDBenchOracleFuzzySnapshotAclTest#testCreateNodeRecoversPurgedACL`: a `DataTree` node is created with `CREATOR_ALL_ACL`, its ACL entry is purged from the ACL cache, and a create for the same path is replayed.

- **FAIL** (exit 1): reading the node's ACL afterwards (`getACL`) throws a `RuntimeException` or returns a different ACL, or the replayed create does not throw `NodeExistsException`. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): the replayed create throws `NodeExistsException` and the node's ACL then reads back as `CREATOR_ALL_ACL`.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or `zookeeper-server` is missing), or the test produced no JUnit report and no compilation error explains it.
