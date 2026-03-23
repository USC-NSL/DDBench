# Dragonfly #6856: DFLYCLUSTER FLUSHSLOTS with OOB Slot ID Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6856](https://github.com/dragonflydb/dragonfly/issues/6856) |
| Language | C++ |
| Category | Crash (SIGABRT / out-of-bounds) |

## Bug Summary

When running Dragonfly in cluster mode, sending `DFLYCLUSTER FLUSHSLOTS 16384` (or any slot ID >= 16384) causes the process to crash with SIGABRT. The slot ID exceeds the valid range (0-16383) and triggers an out-of-bounds bitset access: `bitset::set: __position (which is 16384) >= _Nb (which is 16384)`.

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
The Dragonfly process crashes with SIGABRT (exit code 134) when FLUSHSLOTS receives an out-of-range slot ID.

**When the bug is fixed (PASS):**
The command returns an error response and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
