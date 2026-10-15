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
# from the repository root
./bench.sh setup dragonfly-6907-ftsearch-vector-crash        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6907-ftsearch-vector-crash    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6907-ftsearch-vector-crash        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes when FT.SEARCH accesses a document with a wrong-sized vector.

**When the bug is fixed (PASS):**
The search handles the mismatched vector gracefully and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
