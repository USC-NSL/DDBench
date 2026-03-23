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
The leasing cache returns data that does not match the actual etcd state (e.g., cache says key exists but etcd says it was deleted, or vice versa).

**When the bug is fixed (PASS):**
The leasing cache always returns data consistent with the actual etcd state across 1000 iterations.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
