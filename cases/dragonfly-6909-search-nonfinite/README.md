# Dragonfly #6909: FT.CREATE with Non-Finite Numeric Value Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6909](https://github.com/dragonflydb/dragonfly/issues/6909) |
| Language | C++ |
| Category | Crash (assertion failure / segfault) |

## Bug Summary

Indexing a document with a non-finite NUMERIC value (NaN, Inf, -Inf) in a search index causes a crash. There is no validation that numeric values are finite before they are used in search index operations. The crash is triggered during `FT.SEARCH` or related search indexing operations.

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
The Dragonfly process crashes when a document with a non-finite numeric value (inf) is indexed and searched.

**When the bug is fixed (PASS):**
The non-finite value is rejected or handled gracefully and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
