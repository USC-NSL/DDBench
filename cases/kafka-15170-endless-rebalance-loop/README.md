# Kafka #15170: CooperativeStickyAssignor Endless Rebalance Loop

| Field | Value |
|-------|-------|
| Project | [Apache Kafka](https://github.com/apache/kafka) |
| Issue | [KAFKA-15170](https://issues.apache.org/jira/browse/KAFKA-15170) |
| PR | [#13965](https://github.com/apache/kafka/pull/13965) |
| Language | Java |
| Category | Correctness / infinite loop (consumer group rebalancing) |

## Bug Summary

The `CooperativeStickyAssignor` fails to correctly adjust assignments during rack-aware rebalancing. When partitions need to be moved between consumers due to rack mismatch, the assignor does not properly track which partitions are transferring ownership. Additionally, the unfilled-members tracking is not correctly cleared when the expected number of maxQuota consumers is reached. These bugs produce invalid assignments that trigger an `IllegalStateException` during an internal correctness check, sending the consumer group into an endless rebalancing loop.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Java 17 (JDK)
- Git

## What to Expect

**When the bug is present (FAIL):**
The regression test fails because `partitionsTransferringOwnership()` returns 0 entries instead of the expected 2. Partitions revoked due to rack mismatch are not tracked for cooperative ownership transfer, causing the consumer group to enter an infinite rebalance loop.

**When the bug is fixed (PASS):**
The test passes because `partitionsTransferringOwnership()` correctly contains 2 entries for partitions that changed ownership due to rack-aware reassignment, and the unfilled members tracking is properly cleared.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
