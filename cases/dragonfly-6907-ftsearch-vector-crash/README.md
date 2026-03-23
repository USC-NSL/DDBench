# Dragonfly #6907: FT.SEARCH on Wrong-Sized Vector Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6907](https://github.com/dragonflydb/dragonfly/issues/6907) |
| Language | C++ |
| Category | Crash (out-of-bounds memory access) |

## Bug Summary

Running `FT.SEARCH` on a search index when documents contain wrong-sized VECTOR field values causes a crash at `doc_accessors.cc:60` due to out-of-bounds memory access. The index expects a specific vector dimension but the stored data has fewer dimensions.

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
- Python 3 with `redis` package (`pip3 install redis`)

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes when FT.SEARCH accesses a document with a wrong-sized vector.

**When the bug is fixed (PASS):**
The search handles the mismatched vector gracefully and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
