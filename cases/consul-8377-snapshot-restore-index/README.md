# Consul #8377: Snapshot Restore Loses Node/Service/Check Indexes

| Field | Value |
|-------|-------|
| Project | [Consul](https://github.com/hashicorp/consul) |
| Issue | [#8377](https://github.com/hashicorp/consul/issues/8377) |
| Language | Go |
| Category | Logic error (data inconsistency across Raft replicas) |

## Bug Summary

When Consul servers restore from Raft snapshots, nodes, services, and health checks are re-inserted with new `CreateIndex`/`ModifyIndex` values derived from the restore index, instead of preserving the original values. Since each server snapshots at a different Raft index, this causes permanent inconsistency across the cluster: stale queries to followers return different index values than the leader, breaking blocking queries and CAS updates.

## Quick Start

```bash
# from the repository root
./bench.sh setup consul-8377-snapshot-restore-index        # build image + case repository, warm caches
./bench.sh reproduce consul-8377-snapshot-restore-index    # FAIL (exit 1) while the bug is present
./bench.sh shell consul-8377-snapshot-restore-index        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/consul` image; see the top-level README).

## Build Notes

- `make dev-build` produces `bin/consul`.

## What to Expect

**When the bug is present (FAIL):**
After restarting the cluster, stale queries to each server return different `CreateIndex` values for the same health check (e.g., `14`, `15`, `16`).

**When the bug is fixed (PASS):**
After restarting the cluster, all servers return the same `CreateIndex` value for the health check.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
