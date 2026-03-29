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
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.22+ (expected at /usr/local/go/bin/go)

## What to Expect

**When the bug is present (FAIL):**
The injected regression test times out because one of the compacted watchers never receives its compaction notification. The channel buffer (size 1) fills up with one notification, and the second watcher's notification is dropped. Despite the failed send, the watcher's revision is silently advanced, so subsequent sync rounds never retry.

**When the bug is fixed (PASS):**
The test passes. All compacted watchers eventually receive their compaction notifications (via retry on subsequent sync rounds), and watchers above the compaction revision receive all their events normally.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
