# Reproduce: Kafka #14334

All commands run inside `./bench.sh shell kafka-14334-delayed-fetch-purgatory`, from the worktree `/workspace/src`. The oracle's harness files are mounted read-only at `/bench/inject_test/`.

## Step 1: Build the broker

```bash
./gradlew jar -x test -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet --no-daemon
```

## Step 2: Put the oracle test in a scratch directory

The test is compiled from outside the worktree.

```bash
mkdir -p /tmp/oracle-src/kafka/server /tmp/oracle-resources
cp /bench/inject_test/DDBenchOracleFetchFromFollowerTest.scala /tmp/oracle-src/kafka/server/
cp /bench/inject_test/log4j.properties /tmp/oracle-resources/
```

## Step 3: Run the oracle test

The init script adds a `ddbenchOracle` source set to `:core` and the task `:core:ddbenchOracleTest`. The source set is compiled against core's main classes, core's main dependencies and JUnit; no test sources of the worktree are compiled.

```bash
DDBENCH_ORACLE_SRC=/tmp/oracle-src DDBENCH_ORACLE_RESOURCES=/tmp/oracle-resources \
    ./gradlew --init-script /bench/inject_test/ddbench-oracle.init.gradle :core:ddbenchOracleTest --no-daemon
```

The test method `testDDBenchOracleFollowerAnswersWaitingFetchOnReplication` starts ZooKeeper and two brokers in the test JVM (ZooKeeper mode, listeners on `localhost`, logs in temporary directories). Fetching from followers is enabled: broker `i` has `broker.rack=ddbench-rack-i`, and both have `replica.selector.class=org.apache.kafka.common.replica.RackAwareReplicaSelector`. Then:

1. It creates the topic `ddbench-oracle-topic` with one partition, replicas `[0, 1]` and `min.insync.replicas=2`. It waits until broker 0 leads the partition with ISR `{0, 1}`, and until both brokers answer a zero-wait consumer fetch (FetchRequest v13) for it themselves, without an error or a preferred-read-replica redirect.
2. Round 1: it sends a consumer FetchRequest for offset 0 with `minBytes=1`, `maxWait=30000` ms and rack `ddbench-rack-1` straight to broker 1, the follower, on its own connection. As a control, it sends the same fetch, with rack `ddbench-rack-0`, to broker 0, the leader. Nothing has been produced yet, so both brokers have to hold their fetch.
3. After 1.5 s it produces one record to the partition through the leader (`acks=all`).
4. The follower must answer its waiting fetch with that record within 10 s of the producer's acknowledgement. If it has not answered by then, the test checks that the leader answered the control fetch with the record within those 10 s and that a zero-wait fetch from the follower already returns the record. It then waits for the follower's late answer and reports when it came.
5. Round 2 repeats steps 2–4 from the next offset, with 15 s between sending the fetches and producing.

## Step 4: Read the results

```bash
grep -h "DDBench oracle:" core/build/test-results/ddbenchOracleTest/*.xml
grep -ho '<failure message="[^"]*"' core/build/test-results/ddbenchOracleTest/*.xml
```

## Expected result (bug present)

The follower answers its fetch only when the fetch's 30 s wait expires. The leader answers the same fetch as soon as the record is committed, and the record is readable on the follower long before the expiry:

```
DDBench oracle: cluster ready: broker 0 leads ddbench-oracle-topic-0, broker 1 follows; consumer fetches use FetchRequest v13
DDBench oracle: round 1: the follower answered it only 30004 ms after it was sent (28387 ms after the ack; maxWait 30000 ms): error NONE, partition error NONE, high watermark 1, preferred read replica -1, 1 record(s) [control: the leader answered -10 ms after the ack (...); zero-wait fetch from the follower 10 s after the ack: error NONE, partition error NONE, high watermark 1, preferred read replica -1, 1 record(s)]
DDBenchOracleFetchFromFollowerTest > testDDBenchOracleFollowerAnswersWaitingFetchOnReplication() FAILED
    org.opentest4j.AssertionFailedError: round 1: a consumer fetch waiting on the follower was not answered within 10000 ms after the record was acknowledged, although the record was readable on the follower by then ...
```

## Expected result (fix applied)

In both rounds the follower answers its waiting fetch with the record shortly after the acknowledgement. With the upstream fix this takes about 0.5 s, the time the follower needs to learn the new high watermark from the leader (`replica.fetch.wait.max.ms`, 500 ms by default):

```
DDBench oracle: round 1: the follower answered the waiting fetch with the record 498 ms after the record was acknowledged (2118 ms after the fetch was sent; maxWait 30000 ms) [control: the leader answered -11 ms after the ack (...)]
DDBench oracle: round 2: the follower answered the waiting fetch with the record 502 ms after the record was acknowledged (15520 ms after the fetch was sent; maxWait 30000 ms) [control: the leader answered 0 ms after the ack (...)]
DDBenchOracleFetchFromFollowerTest > testDDBenchOracleFollowerAnswersWaitingFetchOnReplication() PASSED
```

## Cleanup

```bash
rm -rf /tmp/oracle-src /tmp/oracle-resources
find core/build -maxdepth 5 -iname '*ddbenchoracle*' -prune -exec rm -rf {} +
```

## Oracle verdict

`./bench.sh reproduce kafka-14334-delayed-fetch-purgatory` rebuilds the worktree and runs the oracle (`reproduce.sh`). It runs the test method of Step 3 and reads its JUnit result:

- **FAIL** (exit 1): the test fails. In a round, the follower has not answered its waiting fetch with the record 10 s after the acknowledgement, although by then the leader had answered its identical fetch with the record and a zero-wait fetch from the follower returned the record. It also fails when the follower answers the waiting fetch before any record was produced, answers it without the record or with an error, or closes the connection, and when a broker does not start. A worktree that does not build, or an oracle test that does not compile against it, is also FAIL.
- **PASS** (exit 0): in both rounds the follower answers its waiting fetch with the produced record within 10 s of the acknowledgement.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh`, the core sources, or a file in `inject_test/` is missing). Also ERROR: the test could not establish its preconditions and failed with `DDBenchOracleSetupException`. That covers ZooKeeper not starting; the topic, leader 0 with ISR `{0, 1}`, or a follower serving consumer fetches not reached within 60 s; and the record not acknowledged within 30 s. It also covers the case where the follower did not answer in time but the leader's control fetch was not answered with the record within 10 s either, or the record was not yet readable on the follower 10 s after the acknowledgement. Finally, ERROR when the test did not run and no compilation error explains it.
