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
The injected regression test fails because a watcher with start revision 100 receives events at much lower revisions (e.g., revision 2) after a snapshot restore. The watch contract is violated.

**When the bug is fixed (PASS):**
The test passes. The watcher correctly withholds events with revisions below its requested future start revision, even after a snapshot restore.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
