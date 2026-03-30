# Kafka #14334: Delayed Fetch Purgatory Not Completed on Follower Append

| Field | Value |
|-------|-------|
| Project | [Apache Kafka](https://github.com/apache/kafka) |
| Issue | [KAFKA-14334](https://issues.apache.org/jira/browse/KAFKA-14334) |
| PR | [#12783](https://github.com/apache/kafka/pull/12783) |
| Language | Scala/Java |
| Build | Gradle |
| Category | Performance / Correctness |

## Bug Summary

When a follower replica appends messages received from the leader, the `DelayedFetchPurgatory` is never checked or completed. Consumers configured to fetch from follower replicas always wait the full `fetch.max.wait.ms` timeout before receiving data, even when new messages have already been replicated to the follower. The root cause is that `ReplicaFetcherThread.processPartitionData()` updates the follower's high watermark but never calls `replicaManager.completeDelayedFetchRequests()`, so any pending delayed fetch requests remain stuck in the purgatory until the timeout expires.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Java 17 (expected at `/usr/lib/jvm/java-17-openjdk-amd64`)
- Docker (optional, recommended)

## What to Expect

**When the bug is present (FAIL):**
The injected regression test fails because `ReplicaFetcherThread` does not override `doWork()` to call `completeDelayedFetchRequests()`, and the necessary API methods (`maybeUpdateHighWatermark`, `completeDelayedFetchRequests`, `partitionsWithNewHighWatermark`) are missing from the buggy code.

**When the bug is fixed (PASS):**
The test passes. `ReplicaFetcherThread.doWork()` now calls `completeDelayedFetchRequests()` after each fetch cycle, draining the buffer of partitions whose high watermark changed and completing any pending delayed fetch requests.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
