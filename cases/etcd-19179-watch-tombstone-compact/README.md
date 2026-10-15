# etcd #19179: Missing Delete Event on Watch at Compaction Revision

| Field | Value |
|-------|-------|
| Project | [etcd](https://github.com/etcd-io/etcd) |
| Issue | [#19179](https://github.com/etcd-io/etcd/issues/19179) |
| Language | Go |
| Category | Correctness (watch guarantee violation) |

## Bug Summary

When a key's only remaining revision is a tombstone (delete marker) because all older revisions have been removed by compaction, restarting etcd causes the tombstone to be lost. The `Restore()` function in the MVCC layer skips tombstones that are the first revision encountered for a key during index reconstruction. As a result, a watch starting from a revision at or before the delete never receives the DELETE event, violating etcd's watch guarantees.

## Quick Start

```bash
# from the repository root
./bench.sh setup etcd-19179-watch-tombstone-compact        # build image + case repository, warm caches
./bench.sh reproduce etcd-19179-watch-tombstone-compact    # FAIL (exit 1) while the bug is present
./bench.sh shell etcd-19179-watch-tombstone-compact        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/etcd` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The injected regression test fails because after compaction and restore, the tombstone for the deleted key is not reconstructed in the in-memory key index. Range query results before and after restore differ.

**When the bug is fixed (PASS):**
The test passes. The tombstone is correctly restored into the key index, and Range query results are identical before and after restore.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
