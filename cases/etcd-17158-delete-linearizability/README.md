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
# from the repository root
./bench.sh setup etcd-17158-delete-linearizability        # build image + case repository, warm caches
./bench.sh reproduce etcd-17158-delete-linearizability    # FAIL (exit 1) while the bug is present
./bench.sh shell etcd-17158-delete-linearizability        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/etcd` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The injected regression test fails because after deleting a key, a read via ReadTx still returns the deleted key. The BatchTx and ReadTx return inconsistent results: BatchTx correctly shows the key as deleted, but ReadTx still sees it in the stale buffer.

**When the bug is fixed (PASS):**
The test passes. After deleting a key, both BatchTx and ReadTx agree that the key is gone, because the fix forces an immediate bbolt commit when there are pending delete operations.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
