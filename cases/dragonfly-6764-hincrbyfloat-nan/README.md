# Dragonfly #6764: HINCRBYFLOAT with NaN/Inf Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6764](https://github.com/dragonflydb/dragonfly/issues/6764) |
| Language | C++ |
| Category | Crash (assertion failure) |

## Bug Summary

Running `HINCRBYFLOAT` with `nan` as the increment on a nonexistent hash field creates an invalid internal state. A subsequent `HRANDFIELD` on the same hash triggers a crash at `hset_family.cc:973` because the hash is left in an invalid empty state.

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
The Dragonfly process crashes when HRANDFIELD is called on a hash corrupted by HINCRBYFLOAT with nan.

**When the bug is fixed (PASS):**
The HINCRBYFLOAT command returns an error for non-finite values and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
