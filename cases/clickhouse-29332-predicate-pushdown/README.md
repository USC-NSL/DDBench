# ClickHouse #29332: Predicate Pushdown Incorrectly Rewrites Distributed IN Subqueries

| Field | Value |
|-------|-------|
| Project | [ClickHouse](https://github.com/ClickHouse/ClickHouse) |
| Issue | [#29332](https://github.com/ClickHouse/ClickHouse/issues/29332) |
| Language | C++ |
| Category | Query correctness (incorrect predicate pushdown) |

## Bug Summary

When `enable_optimize_predicate_expression` is enabled (the default), queries combining GROUP BY on a distributed table with a `WHERE id IN (SELECT ... FROM distributed_table)` clause are incorrectly rewritten. The optimizer pushes the IN predicate containing a distributed subquery down into the distributed table's inner query, creating a double-distributed query that violates `distributed_product_mode='deny'` and causes a `DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED` error.

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
The query fails with `Code: 288. DB::Exception: DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED`.

**When the bug is fixed (PASS):**
The query returns results successfully with exit code 0.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
