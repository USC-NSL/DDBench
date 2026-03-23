# Dragonfly #6619: EVALSHA with Empty SHA Causes Assertion Failure

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6619](https://github.com/dragonflydb/dragonfly/issues/6619) |
| Language | C++ |
| Category | Crash (SIGABRT / assertion failure) |

## Bug Summary

Sending `EVALSHA "" 0` (with an empty SHA string) causes the Dragonfly process to crash with an assertion failure (`Check failed: !eval_args.sha.empty()`). The empty SHA is not validated before being used.

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
The Dragonfly process crashes with SIGABRT (exit code 134) immediately upon receiving `EVALSHA "" 0`.

**When the bug is fixed (PASS):**
The command returns an error response and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
