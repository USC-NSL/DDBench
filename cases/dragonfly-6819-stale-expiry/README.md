# Dragonfly #6819: Stale Expiry After SORT STORE Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6819](https://github.com/dragonflydb/dragonfly/issues/6819) |
| Language | C++ |
| Category | Crash (assertion failure) |

## Bug Summary

When a key is set with an expiry (`SET key val PX 500`) and then overwritten via `SORT key STORE key`, the stale expiry entry is not cleared. When the original expiry time arrives, the expiry cycle attempts to expire the key, leading to a crash at `db_slice.cc:1163`.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- C++ compiler (GCC 11+ or Clang 14+)
- CMake 3.16+
- Ninja build system
- `redis-cli` (from redis-tools package)

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes when the stale expiry fires after the key has been overwritten by SORT STORE.

**When the bug is fixed (PASS):**
The expiry is properly cleared on overwrite and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
