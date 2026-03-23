# Dragonfly #6614: MONITOR Inside MULTI/EXEC Causes Assertion Failure

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6614](https://github.com/dragonflydb/dragonfly/issues/6614) |
| Language | C++ |
| Category | Crash (SIGABRT / assertion failure) |

## Bug Summary

Calling MONITOR twice inside a MULTI/EXEC block causes `ChangeMonitor` to add the connection twice, triggering an assertion failure (`Check failed: cc_`). The process crashes with SIGABRT.

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
The Dragonfly process crashes with SIGABRT (exit code 134) when MONITOR is called twice inside MULTI/EXEC.

**When the bug is fixed (PASS):**
The command completes without crashing and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
