# Kafka #15784: Transactional Offset Commit Atomicity Violation

| Field | Value |
|-------|-------|
| Project | [Apache Kafka](https://github.com/apache/kafka) |
| Issue | [KAFKA-15784](https://issues.apache.org/jira/browse/KAFKA-15784) |
| PR | [#14774](https://github.com/apache/kafka/pull/14774) |
| Language | Scala/Java |
| Category | Correctness (atomicity violation) |

## Bug Summary

`GroupMetadataManager.storeOffsets` updates consumer group offsets in memory (`prepareTxnOffsetCommit`) BEFORE the transaction log write completes. If the log append fails with an exception (not just an error returned via callback), the in-memory failure callback is never invoked, leaving the group with stale pending offsets that diverge from persisted state.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Java 17 (openjdk-17-jdk)
- ~10 GB disk space for Gradle build

## What to Expect

**When the bug is present (FAIL):**
The injected test fails because after a log append exception during a transactional offset commit, the group retains stale pending offsets in memory. `prepareTxnOffsetCommit` was called before `appendRecords`, and the exception skipped the failure callback that would have cleaned up the state.

**When the bug is fixed (PASS):**
The test passes. The fix refactors `storeOffsets` to separate record generation from in-memory state updates, ensuring the in-memory update only happens inside the append callback.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
