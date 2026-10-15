# Kafka #15784: Transactional Offset Commits Diverge from the Offsets Log

| Field | Value |
|-------|-------|
| Project | [Apache Kafka](https://github.com/apache/kafka) |
| Issue | [KAFKA-15784](https://issues.apache.org/jira/browse/KAFKA-15784) |
| Language | Scala |
| Category | Data inconsistency (group coordinator cache vs. `__consumer_offsets` log) |

## Bug Summary

With transaction verification enabled (the default), a transactional offset commit that overlaps with the deletion of its (empty) consumer group, or with the coordinator unloading and reloading the group's `__consumer_offsets` partition, is acknowledged and written to the log, but after the transaction commits the coordinator does not serve the committed offset. A coordinator that reloads the partition serves it, so the offsets consumers see change across a coordinator failover.

## Quick Start

```bash
# From the repository root
./bench.sh setup kafka-15784-txn-offset-atomicity       # image, truncated case repository, build, dependency warm-up
./bench.sh reproduce kafka-15784-txn-offset-atomicity   # run the oracle: exit 0 PASS, 1 FAIL, 2 ERROR
./bench.sh shell kafka-15784-txn-offset-atomicity       # interactive shell in /workspace/src; rerun with: bash /bench/reproduce.sh
```

Prerequisites: Docker. The JDK is in the `bug-bench/kafka` image and Gradle comes with the repository's wrapper. The case builds `:core:jar` (the broker core and the modules it depends on), not the whole Kafka build.

## What to Expect

The oracle runs a single-broker group coordinator on a real `__consumer_offsets` log, with transaction verification enabled and the transaction coordinator simulated. It runs three scenarios: a plain transactional offset commit (baseline), a commit that overlaps with `DeleteGroups`, and a commit that overlaps with the coordinator unloading and reloading the offsets partition. After each transaction completes, it compares the offset the live coordinator serves with the offset a new coordinator serves after reloading the log.

**When the bug is present (FAIL):**
The baseline passes. In both overlapping scenarios the commit is acknowledged and the transaction commits, but the live coordinator serves offset `-1` while a reloaded coordinator serves `10`.

**When the bug is fixed (PASS):**
In every scenario the live and the reloaded coordinator serve the same offset (`10` once the producer's commit is acknowledged and the transaction commits; the producer retries retriable errors).

## Oracle harness files

- [`inject_test/DDBenchOracleTxnOffsetCommitTest.scala`](inject_test/DDBenchOracleTxnOffsetCommitTest.scala): the oracle test (JUnit 5, package `kafka.coordinator.group`).
- [`inject_test/ddbench-oracle.init.gradle`](inject_test/ddbench-oracle.init.gradle): Gradle init script that compiles the test from a scratch directory in its own source set of `:core` (against core's main classes and test dependencies, not core's own test sources) and runs it as `:core:ddbenchOracleTest`.

## Detailed Documentation

- [`symptom.md`](symptom.md): observable behavior and error messages
- [`reproduce.md`](reproduce.md): step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh): the oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
