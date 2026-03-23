# Dragonfly #6738: Pipeline Replies Blocked by BLPOP

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6738](https://github.com/dragonflydb/dragonfly/issues/6738) |
| Language | C++ |
| Category | Pipeline blocking (reply flushing) |

## Bug Summary

When non-blocking commands (SET, PING) are sent in a pipeline followed by a blocking command (BLPOP), all replies are held back until the blocking command completes or times out. The replies for SET and PING should be flushed immediately, but instead they are delayed by the BLPOP timeout.

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
The entire pipeline (including SET and PING replies) is delayed ~5 seconds until BLPOP times out. All replies are flushed together at the end.

**When the bug is fixed (PASS):**
SET and PING replies are flushed immediately. Only the BLPOP response is delayed until its timeout.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
