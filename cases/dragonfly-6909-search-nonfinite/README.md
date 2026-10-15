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
# from the repository root
./bench.sh setup dragonfly-6909-search-nonfinite        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6909-search-nonfinite    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6909-search-nonfinite        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes when a document with a non-finite numeric value (inf) is indexed and searched.

**When the bug is fixed (PASS):**
The non-finite value is rejected or handled gracefully and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
