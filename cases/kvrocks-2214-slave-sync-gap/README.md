# Kvrocks #2214: Slave Loses Key Updates After Restart

| Field | Value |
|-------|-------|
| Project | [Kvrocks](https://github.com/apache/kvrocks) |
| Issue | [#2214](https://github.com/apache/kvrocks/issues/2214) |
| Language | C++ |
| Category | Data Consistency (silent replication gap) |

## Bug Summary

When `repl-namespace-enabled` is turned on, a slave that restarts fails to receive keys that were updated on the master during the slave's downtime. The slave reconnects and appears fully synced, but some keys remain stale or missing. This is a silent data consistency bug -- no errors are logged and the replication status shows everything is healthy.

## Quick Start

```bash
# from the repository root
./bench.sh setup kvrocks-2214-slave-sync-gap        # build image + case repository, warm caches
./bench.sh reproduce kvrocks-2214-slave-sync-gap    # FAIL (exit 1) while the bug is present
./bench.sh shell kvrocks-2214-slave-sync-gap        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/kvrocks` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
After the slave restarts and reconnects, keys updated on the master during the slave's downtime are stale or missing on the slave. For example, `test1` still has its old value instead of the updated one.

**When the bug is fixed (PASS):**
After the slave restarts and reconnects, all keys updated on the master during downtime are correctly replicated to the slave.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
