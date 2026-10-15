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

When a follower replica appends messages received from the leader, the `DelayedFetchPurgatory` is never checked or completed. Consumers configured to fetch from follower replicas always wait the full `fetch.max.wait.ms` timeout before receiving data, even when new messages have already been replicated to the follower. The root cause is that `ReplicaFetcherThread.processPartitionData()` advances the follower's high watermark but nothing then checks the follower's delayed fetch purgatory, so pending consumer fetches stay there until they expire.

## Quick Start

```bash
# from the repository root
./bench.sh setup kafka-14334-delayed-fetch-purgatory        # build image + case repository, warm caches
./bench.sh reproduce kafka-14334-delayed-fetch-purgatory    # FAIL (exit 1) while the bug is present
./bench.sh shell kafka-14334-delayed-fetch-purgatory        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/kafka` image; see the top-level README).

## What to Expect

The oracle starts two brokers in-process (fetch from follower enabled, broker 0 leading and broker 1 following a replicated partition). It sends a consumer fetch (`minBytes=1`, `maxWait=30 s`) to the follower before producing, then produces one record to the leader with `acks=all`, in two rounds.

**When the bug is present (FAIL):**
The follower holds the fetch until its 30 s `maxWait` expires (about 28 s after the record was acknowledged), although the same fetch sent to the leader is answered at once and the record is already readable on the follower.

**When the bug is fixed (PASS):**
The follower answers the waiting fetch with the record well within 10 s of the acknowledgement (about half a second with the upstream fix), in both rounds.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
