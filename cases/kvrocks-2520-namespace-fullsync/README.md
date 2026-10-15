# Kvrocks #2520: Namespaces Not Loaded After Full Sync from Master

| Field | Value |
|-------|-------|
| Project | [Kvrocks](https://github.com/apache/kvrocks) |
| Issue | [#2520](https://github.com/apache/kvrocks/issues/2520) |
| Language | C++ |
| Category | Replication (stale namespace state after full sync) |

## Bug Summary

After a replica performs `SLAVEOF` from a master with multiple namespaces, only the default namespace is visible on the replica. The namespace data is transferred during full sync but is not accessible until the replica is restarted.

## Quick Start

```bash
# from the repository root
./bench.sh setup kvrocks-2520-namespace-fullsync        # build image + case repository, warm caches
./bench.sh reproduce kvrocks-2520-namespace-fullsync    # FAIL (exit 1) while the bug is present
./bench.sh shell kvrocks-2520-namespace-fullsync        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/kvrocks` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
Only the default namespace is visible on the slave after full sync. Running `NAMESPACE GET *` on the slave shows only `__namespace`. Namespaces `ns1` and `ns2` are missing despite being present on the master.

**When the bug is fixed (PASS):**
All namespaces (`ns1`, `ns2`, and default) are visible on the slave immediately after full sync completes, without requiring a server restart.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
