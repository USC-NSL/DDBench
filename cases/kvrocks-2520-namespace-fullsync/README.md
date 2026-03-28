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
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- C++ compiler (GCC 7+ or Clang)
- CMake 3.16+
- `redis-cli` (from redis-tools package)

## What to Expect

**When the bug is present (FAIL):**
Only the default namespace is visible on the slave after full sync. Running `NAMESPACE GET *` on the slave shows only `__namespace`. Namespaces `ns1` and `ns2` are missing despite being present on the master.

**When the bug is fixed (PASS):**
All namespaces (`ns1`, `ns2`, and default) are visible on the slave immediately after full sync completes, without requiring a server restart.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
