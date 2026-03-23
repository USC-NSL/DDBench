# Kvrocks #3315: ZDIFF with numkeys=0 Causes Process Crash

| Field | Value |
|-------|-------|
| Project | [Kvrocks](https://github.com/apache/kvrocks) |
| Issue | [#3315](https://github.com/apache/kvrocks/issues/3315) |
| Language | C++ |
| Category | Crash (out-of-bounds access) |

## Bug Summary

Sending `ZDIFF 0 a` (with `numkeys=0`) to Kvrocks causes the server process to crash due to an out-of-bounds array access when the number of keys is zero. All client connections are dropped.

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
The Kvrocks process crashes immediately upon receiving `ZDIFF 0 a`.

**When the bug is fixed (PASS):**
The command returns an error response (e.g., "at least 1 input key is needed") and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
