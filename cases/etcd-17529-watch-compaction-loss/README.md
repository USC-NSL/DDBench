# etcd #17529: Watch Event Loss After Compaction

| Field | Value |
|-------|-------|
| Project | [etcd](https://github.com/etcd-io/etcd) |
| Issue | [#17529](https://github.com/etcd-io/etcd/issues/17529) |
| Language | Go |
| Category | Correctness (watch event loss) |

## Bug Summary

When the watch synchronization loop processes watchers whose start revision is below the compaction revision, it attempts to send a compaction notification. If the watch channel buffer is full, the notification is silently dropped. Despite this failure, the watcher's minimum revision is advanced past the compaction point, permanently preventing the compaction notification from being retried. The watcher becomes stuck: it neither receives the compaction error nor the events it missed.

## Quick Start

```bash
# from the repository root
./bench.sh setup etcd-17529-watch-compaction-loss        # build image + case repository, warm caches
./bench.sh reproduce etcd-17529-watch-compaction-loss    # FAIL (exit 1) while the bug is present
./bench.sh shell etcd-17529-watch-compaction-loss        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/etcd` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The injected regression test times out because one of the compacted watchers never receives its compaction notification. The channel buffer (size 1) fills up with one notification, and the second watcher's notification is dropped. Despite the failed send, the watcher's revision is silently advanced, so subsequent sync rounds never retry.

**When the bug is fixed (PASS):**
The test passes. All compacted watchers eventually receive their compaction notifications (via retry on subsequent sync rounds), and watchers above the compaction revision receive all their events normally.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
