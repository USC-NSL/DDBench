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
# from the repository root
./bench.sh setup dragonfly-6912-rdb-encoding        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6912-rdb-encoding    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6912-rdb-encoding        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes with `FATAL: Unknown encoding 0 for type 17` when DUMP is called on a CMS key.

**When the bug is fixed (PASS):**
The DUMP command returns the serialized data and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
