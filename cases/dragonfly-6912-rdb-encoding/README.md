# Dragonfly #6912: DUMP on CMS Key Causes Fatal Unknown Encoding Error

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6912](https://github.com/dragonflydb/dragonfly/issues/6912) |
| Language | C++ |
| Category | Crash (fatal error / unknown encoding) |

## Bug Summary

Using the `DUMP` command on a key that holds a CMS (Count-Min Sketch) data structure causes a fatal crash: `FATAL: Unknown encoding 0 for type 17`. The `RdbObjectType` serialization function in `rdb_save.cc` does not handle the CMS type. Any operation that triggers RDB serialization of a CMS key (DUMP, BGSAVE, replication) will crash.

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
The Dragonfly process crashes with `FATAL: Unknown encoding 0 for type 17` when DUMP is called on a CMS key.

**When the bug is fixed (PASS):**
The DUMP command returns the serialized data and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
