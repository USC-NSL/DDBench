# ClickHouse #75699: LOGICAL_ERROR on JOIN with Merge over Distributed Table

| Field | Value |
|-------|-------|
| Project | [ClickHouse](https://github.com/ClickHouse/ClickHouse) |
| Issue | [#75699](https://github.com/ClickHouse/ClickHouse/issues/75699) |
| Language | C++ |
| Category | Crash (LOGICAL_ERROR) |

## Bug Summary

When performing a JOIN query where the left table is a Merge table backed by a Distributed table, ClickHouse crashes with a `Code: 49 LOGICAL_ERROR` exception. The error occurs internally in the query execution pipeline due to an invalid column source node. The crash is deterministic and triggered specifically by the combination of Merge table wrapping a Distributed table in a JOIN context.

## Quick Start

```bash
# 1. Clone, checkout, and build ClickHouse from source
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- git, cmake, ninja-build
- C++ compiler (clang 14+ or GCC 11+)
- At least 16 GB RAM, 30 GB disk space
- Build time: 30-90 minutes

## What to Expect

**When the bug is present (FAIL):**
The JOIN query fails with `Code: 49. DB::Exception: LOGICAL_ERROR`.

**When the bug is fixed (PASS):**
The query returns results successfully.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
