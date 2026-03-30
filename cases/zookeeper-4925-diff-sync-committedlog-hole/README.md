# ZooKeeper #4925: Diff Sync CommittedLog Hole

| Field | Value |
|-------|-------|
| Project | [ZooKeeper](https://github.com/apache/zookeeper) |
| Issue | [ZOOKEEPER-4925](https://issues.apache.org/jira/browse/ZOOKEEPER-4925) |
| Language | Java |
| Category | Data loss (ZAB protocol correctness) |

## Bug Summary

After a stale follower rejoins via DIFF sync, its in-memory `committedLog` has a hole because the ZOOKEEPER-4394 fix switched `processTxn` to a variant that does not populate `committedLog` during SYNCHRONIZATION. If this follower later becomes leader, the hole propagates to other stale nodes via DIFF sync, causing silent data loss.

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
The regression test fails because after a stale follower rejoins via DIFF sync and later becomes leader, committed znodes are missing. The `committedLog` hole causes the leader to serve incomplete DIFF syncs to other stale nodes.

**When the bug is fixed (PASS):**
All committed znodes are present on all nodes after leader failover and DIFF sync. The `committedLog` is properly populated during SYNCHRONIZATION.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
