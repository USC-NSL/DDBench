# ClickHouse #99109: SUM of Float64 Returns Non-deterministic Results with Different Thread Counts

| Field | Value |
|-------|-------|
| Project | [ClickHouse](https://github.com/ClickHouse/ClickHouse) |
| Issue | [#99109](https://github.com/ClickHouse/ClickHouse/issues/99109) |
| Language | C++ |
| Category | Query correctness (non-deterministic results) |

## Bug Summary

Running `SELECT key, sum(value) FROM table GROUP BY key` on a table with Float64 values produces different results depending on the `max_threads` setting. With `max_threads=1` and `max_threads=16`, the same query on the same data returns slightly different sums. The difference is small (14th-15th decimal digit) but non-zero and reproducible, making deterministic queries produce non-deterministic results.

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
The sums differ between single-threaded and multi-threaded execution (at least some keys show non-zero diff).

**When the bug is fixed (PASS):**
All sums are identical regardless of thread count.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
