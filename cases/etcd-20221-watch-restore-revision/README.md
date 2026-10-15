# etcd #20221: Watch on Future Revision Receives Old Events After Snapshot Restore

| Field | Value |
|-------|-------|
| Project | [etcd](https://github.com/etcd-io/etcd) |
| Issue | [#20221](https://github.com/etcd-io/etcd/issues/20221) |
| Language | Go |
| Category | Correctness (watch contract violation) |

## Bug Summary

After a snapshot restore (as happens when a follower catches up from a leader), watches that were created with a future start revision incorrectly receive events with revisions lower than their requested starting point. This violates the watch API guarantee that a watcher should never see events before its specified start revision.

## Quick Start

```bash
# from the repository root
./bench.sh setup etcd-20221-watch-restore-revision        # build image + case repository, warm caches
./bench.sh reproduce etcd-20221-watch-restore-revision    # FAIL (exit 1) while the bug is present
./bench.sh shell etcd-20221-watch-restore-revision        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/etcd` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The injected regression test fails because a watcher with start revision 100 receives events at much lower revisions (e.g., revision 2) after a snapshot restore. The watch contract is violated.

**When the bug is fixed (PASS):**
The test passes. The watcher correctly withholds events with revisions below its requested future start revision, even after a snapshot restore.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
