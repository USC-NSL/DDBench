# ClickHouse #92375: DISTINCT Returns Wrong Results with optimize_skip_unused_shards on Distributed Table

| Field | Value |
|-------|-------|
| Project | [ClickHouse](https://github.com/ClickHouse/ClickHouse) |
| Issue | [#92375](https://github.com/ClickHouse/ClickHouse/issues/92375) |
| Language | C++ |
| Category | Query correctness (wrong results) |

## Bug Summary

When running `SELECT count() FROM (SELECT DISTINCT number FROM distributed_table)` on a Distributed table backed by two shards, the result changes depending on the `optimize_skip_unused_shards` setting. With the setting disabled (default), the query correctly returns 2 distinct values. With the setting enabled, it incorrectly returns 4, as if DISTINCT deduplication across shards is skipped entirely. The bug requires `enable_analyzer=1`.

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
`optimize_skip_unused_shards=1` returns 4 instead of the correct value 2.

**When the bug is fixed (PASS):**
Both settings return 2.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
