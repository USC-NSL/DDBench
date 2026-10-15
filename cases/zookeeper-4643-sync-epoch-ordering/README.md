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
# from the repository root
./bench.sh setup zookeeper-4643-sync-epoch-ordering        # build image + case repository, warm caches
./bench.sh reproduce zookeeper-4643-sync-epoch-ordering    # FAIL (exit 1) while the bug is present
./bench.sh shell zookeeper-4643-sync-epoch-ordering        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/zookeeper` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The regression test fails because uncommitted proposals are persisted to disk during NEWLEADER processing, before the epoch update. The transaction log contains uncommitted data.

**When the bug is fixed (PASS):**
Only committed transactions are persisted before the epoch update. The test passes, verifying correct ordering of persistence vs epoch update.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
