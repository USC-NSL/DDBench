# Reproduce: Kafka #15784

All commands run inside `./bench.sh shell kafka-15784-txn-offset-atomicity`, from the worktree `/workspace/src`. The oracle's harness files are mounted read-only at `/bench/inject_test/`.

## Step 1: Build the broker core

```bash
./gradlew :core:jar -x test -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet --no-daemon
```

## Step 2: Put the oracle test in a scratch directory

The test is compiled from outside the worktree.

```bash
mkdir -p /tmp/oracle-src/kafka/coordinator/group
cp /bench/inject_test/DDBenchOracleTxnOffsetCommitTest.scala /tmp/oracle-src/kafka/coordinator/group/
```

## Step 3: Run the oracle test

The init script adds a `ddbenchOracle` source set to `:core` (compiled against core's main classes and core's test dependencies) and the task `:core:ddbenchOracleTest`.

```bash
DDBENCH_ORACLE_SRC=/tmp/oracle-src ./gradlew --init-script /bench/inject_test/ddbench-oracle.init.gradle \
    :core:ddbenchOracleTest --no-daemon
```

Each test method starts one broker (`broker.id=0`, `offsets.topic.num.partitions=1`, `offsets.topic.replication.factor=1`, `transaction.partition.verification.enable=true`) with a real `ReplicaManager` and log in a temporary directory. The broker leads `__consumer_offsets-0`. The transaction coordinator is simulated: the test holds the broker's verification requests and answers them with "verified". Then:

1. `testDDBenchOracleTxnOffsetCommitBaseline`: the producer (`producerId=4242`, epoch 0) commits offset 10 for `ddbench-oracle-input-0` in the empty group `ddbench-oracle-group` (generation -1). The verification is answered, the commit marker is written to `__consumer_offsets-0`, and the group coordinator is notified.
2. `testDDBenchOracleGroupDeletedDuringTxnOffsetCommit`: like 1, but `DeleteGroups` runs for the group after the commit request is sent and before its verification is answered.
3. `testDDBenchOracleCoordinatorReloadDuringTxnOffsetCommit`: like 1, but the coordinator resigns from `__consumer_offsets-0` and is elected again (unload, then reload) before the verification is answered.

The producer side of the test retries retriable errors, commits the transaction when the offset commit is acknowledged and aborts it otherwise. Afterwards the test reads the offset the live coordinator serves (`OffsetFetch`, `requireStable=true`), shuts that coordinator down, starts a new one that loads `__consumer_offsets-0`, and reads the offset again.

## Step 4: Read the results

```bash
grep -h "DDBench oracle:" core/build/test-results/ddbenchOracleTest/*.xml
ls core/build/test-results/ddbenchOracleTest/
```

## Expected result (bug present)

The baseline passes. Tests 2 and 3 fail:

```
DDBench oracle: [the group was deleted while the offset commit was in progress] TxnOffsetCommit=NONE, transaction COMMIT, live coordinator serves -1, reloaded coordinator serves 10
DDBenchOracleTxnOffsetCommitTest > testDDBenchOracleGroupDeletedDuringTxnOffsetCommit() FAILED
    org.opentest4j.AssertionFailedError: ... the coordinator serves offset -1 for ddbench-oracle-input-0, but a coordinator that reloads __consumer_offsets serves 10 ...
DDBench oracle: [the coordinator unloaded and reloaded the offsets partition while the offset commit was in progress] TxnOffsetCommit=NONE, transaction COMMIT, live coordinator serves -1, reloaded coordinator serves 10
DDBenchOracleTxnOffsetCommitTest > testDDBenchOracleCoordinatorReloadDuringTxnOffsetCommit() FAILED
```

## Cleanup

```bash
rm -rf /tmp/oracle-src
find core/build -maxdepth 5 -iname '*ddbenchoracle*' -prune -exec rm -rf {} +
```

## Oracle verdict

`./bench.sh reproduce kafka-15784-txn-offset-atomicity` rebuilds the worktree and runs the oracle (`reproduce.sh`), which runs the three test methods of Step 3 and reads their JUnit results:

- **FAIL** (exit 1): any method fails or is skipped: after the transaction completes, the live coordinator serves a different offset than a coordinator reloaded from `__consumer_offsets-0` (e.g. -1 vs 10), the served offset is not 10 after a committed transaction (-1 after an aborted one), the broker answers the commit without waiting for the simulated transaction verification, or the commit is never answered within 60 s or still fails after 5 attempts. A worktree that does not build, or an oracle test that does not compile against it, is also FAIL.
- **PASS** (exit 0): all three methods pass: in every scenario the live and reloaded coordinators serve the same offset, 10 after a committed transaction and -1 after an aborted one (the baseline must commit).
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh`, the core sources, or a file in `inject_test/` is missing), or a test method did not run and no compilation error explains it.
