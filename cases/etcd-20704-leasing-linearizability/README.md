# etcd #20704: Leasing Cache Linearizability Violation Under Concurrent Delete+Put

| Field | Value |
|-------|-------|
| Project | [etcd](https://github.com/etcd-io/etcd) |
| Issue | [#20704](https://github.com/etcd-io/etcd/issues/20704) |
| Language | Go |
| Category | Linearizability violation (correctness bug) |

## Bug Summary

The `client/v3/leasing` cache promises linearizable reads but violates this guarantee under concurrent modifications. When concurrent `Delete` and `Put` operations race, the leasing cache can return stale data that does not match the actual state in etcd, breaking the linearizability contract.

## Quick Start

```bash
# from the repository root
./bench.sh setup etcd-20704-leasing-linearizability        # build image + case repository, warm caches
./bench.sh reproduce etcd-20704-leasing-linearizability    # FAIL (exit 1) while the bug is present
./bench.sh shell etcd-20704-leasing-linearizability        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/etcd` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The leasing cache returns data that does not match the actual etcd state (e.g., cache says key exists but etcd says it was deleted, or vice versa).

**When the bug is fixed (PASS):**
The leasing cache always returns data consistent with the actual etcd state across 1000 iterations.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
