# Dragonfly #6753: DEBUG POPULATE with val_size=0 Causes SIGFPE

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6753](https://github.com/dragonflydb/dragonfly/issues/6753) |
| Language | C++ |
| Category | Crash (SIGFPE / division by zero) |

## Bug Summary

Running `DEBUG POPULATE 100 prefix 0` (with `val_size=0`) causes the Dragonfly process to crash with SIGFPE. The `DoPopulateBatch()` function in `DebugCmd` performs a division by `val_size` without checking for zero.

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
The Dragonfly process crashes with SIGFPE (exit code 136) immediately upon receiving `DEBUG POPULATE 100 prefix 0`.

**When the bug is fixed (PASS):**
The command returns an error response and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
