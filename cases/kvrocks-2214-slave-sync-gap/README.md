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
After the slave restarts and reconnects, keys updated on the master during the slave's downtime are stale or missing on the slave. For example, `test1` still has its old value instead of the updated one.

**When the bug is fixed (PASS):**
After the slave restarts and reconnects, all keys updated on the master during downtime are correctly replicated to the slave.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
