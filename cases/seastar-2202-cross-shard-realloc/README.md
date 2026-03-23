# Seastar #2202: Cross-Shard realloc Shrink Causes Assertion Crash

| Field | Value |
|-------|-------|
| Project | [Seastar](https://github.com/scylladb/seastar) |
| Issue | [#2202](https://github.com/scylladb/seastar/issues/2202) |
| Language | C++ |
| Category | Crash (assertion failure) |

## Bug Summary

When a memory buffer is allocated on one shard (CPU core) and then `realloc`'d to a smaller size on a different shard, Seastar's memory allocator crashes with an assertion failure: `object_cpu_id(ptr) == cpu_id`. The realloc shrink path assumes the object belongs to the current shard and asserts this, but cross-shard realloc is a valid operation that should be handled gracefully (similar to how cross-shard `free` is already handled).

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build, compile test)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- C++ compiler (GCC 11+ or Clang 14+)
- CMake 3.16+
- Ninja build system
- Seastar dependencies (installed by `install-dependencies.sh`)

## What to Expect

**When the bug is present (FAIL):**
The process crashes with assertion failure `object_cpu_id(ptr) == cpu_id` (exit code 134 / SIGABRT).

**When the bug is fixed (PASS):**
The cross-shard realloc shrink completes without crash.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
