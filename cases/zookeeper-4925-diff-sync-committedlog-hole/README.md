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
# from the repository root
./bench.sh setup zookeeper-4925-diff-sync-committedlog-hole        # build image + case repository, warm caches
./bench.sh reproduce zookeeper-4925-diff-sync-committedlog-hole    # FAIL (exit 1) while the bug is present
./bench.sh shell zookeeper-4925-diff-sync-committedlog-hole        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/zookeeper` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The regression test fails because after a stale follower rejoins via DIFF sync and later becomes leader, committed znodes are missing. The `committedLog` hole causes the leader to serve incomplete DIFF syncs to other stale nodes.

**When the bug is fixed (PASS):**
All committed znodes are present on all nodes after leader failover and DIFF sync. The `committedLog` is properly populated during SYNCHRONIZATION.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
