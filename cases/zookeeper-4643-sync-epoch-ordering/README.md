# ZooKeeper #4643: Follower Sync Epoch Ordering

| Field | Value |
|-------|-------|
| Project | [ZooKeeper](https://github.com/apache/zookeeper) |
| Issue | [ZOOKEEPER-4643](https://issues.apache.org/jira/browse/ZOOKEEPER-4643) |
| Language | Java |
| Category | Data loss (ZAB protocol correctness) |

## Bug Summary

During ZAB synchronization, a follower updates `currentEpoch` on disk before persisting synced transactions to the transaction log. If the follower crashes between these operations, it can later be elected leader with incomplete history but higher epoch, issuing improper TRUNC commands that cause committed data loss.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Java 11 (JDK)
- Maven 3.8+
- Git

## What to Expect

**When the bug is present (FAIL):**
The regression test fails because uncommitted proposals are persisted to disk during NEWLEADER processing, before the epoch update. The transaction log contains uncommitted data.

**When the bug is fixed (PASS):**
Only committed transactions are persisted before the epoch update. The test passes, verifying correct ordering of persistence vs epoch update.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
