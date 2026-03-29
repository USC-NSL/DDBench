# etcd #17158: UnsafeDelete Breaks Linearizability

| Field | Value |
|-------|-------|
| Project | [etcd](https://github.com/etcd-io/etcd) |
| Issue | [#17158](https://github.com/etcd-io/etcd/issues/17158) |
| Language | Go |
| Category | Correctness (linearizability violation) |

## Bug Summary

etcd uses a buffered batch transaction layer on top of bbolt. Put operations are buffered so that reads can see uncommitted writes by checking both bbolt and the in-memory buffer. However, delete operations bypass this buffer entirely. When a key is deleted but the bbolt transaction has not yet been committed (etcd commits periodically, not on every request), a subsequent read still sees the deleted key in the stale buffer. This violates linearizability: a read after a delete returns data that should no longer exist.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.21+ (expected at /usr/local/go/bin/go)

## What to Expect

**When the bug is present (FAIL):**
The injected regression test fails because after deleting a key, a read via ReadTx still returns the deleted key. The BatchTx and ReadTx return inconsistent results: BatchTx correctly shows the key as deleted, but ReadTx still sees it in the stale buffer.

**When the bug is fixed (PASS):**
The test passes. After deleting a key, both BatchTx and ReadTx agree that the key is gone, because the fix forces an immediate bbolt commit when there are pending delete operations.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
