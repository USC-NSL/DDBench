# Dragonfly #6825: DFLYCLUSTER CONFIG with Overflow Value Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6825](https://github.com/dragonflydb/dragonfly/issues/6825) |
| Language | C++ |
| Category | Crash (SIGABRT / assertion failure) |

## Bug Summary

When running Dragonfly in cluster mode, sending a `DFLYCLUSTER CONFIG` command with values that cause integer overflow during parsing results in an assertion failure (`Check failed: rb->RepliesRecorded() > replies_recorded_`) and process crash with SIGABRT.

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
The Dragonfly process crashes with SIGABRT (exit code 134) when DFLYCLUSTER CONFIG receives an overflow value.

**When the bug is fixed (PASS):**
The command returns an error response and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
