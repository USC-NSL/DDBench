# Dragonfly #6761: Memcached Pipeline with VERSION/STATS Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6761](https://github.com/dragonflydb/dragonfly/issues/6761) |
| Language | C++ |
| Category | Crash (SIGABRT / unhandled WOULD_BLOCK) |

## Bug Summary

When using the memcached protocol, sending pipelined commands where a `get` precedes a `version` or `stats` command causes a crash. The `version` and `stats` commands return `WOULD_BLOCK` which is not properly handled in the pipeline batch execution path (`Connection::ExecuteMCBatch()`).

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
- `nc` (netcat)

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes with SIGABRT when pipelined memcached commands include VERSION or STATS after a GET.

**When the bug is fixed (PASS):**
The pipelined commands complete normally and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
