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
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.23+ (expected at /usr/local/go/bin/go)

## What to Expect

**When the bug is present (FAIL):**
The injected regression test fails because after compaction and restore, the tombstone for the deleted key is not reconstructed in the in-memory key index. Range query results before and after restore differ.

**When the bug is fixed (PASS):**
The test passes. The tombstone is correctly restored into the key index, and Range query results are identical before and after restore.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
