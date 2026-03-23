# RocksDB #10751: DB::Close() Hangs When Writes Are Stalled

| Field | Value |
|-------|-------|
| Project | [RocksDB](https://github.com/facebook/rocksdb) |
| Issue | [#10751](https://github.com/facebook/rocksdb/issues/10751) |
| Language | C++ |
| Category | Deadlock / Hang |

## Bug Summary

When `DB::Close()` is called while write operations are stalled (blocked by the write rate limiter or L0 stop-writes conditions), the `Close()` call hangs indefinitely. Stalled writer threads wait on a condition variable that is never signaled during shutdown, creating a deadlock: `Close()` waits for background work to finish, but stalled writers will never complete because the shutdown sequence does not release them.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build, compile test)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- CMake 3.16+
- C++ compiler (GCC 11+)
- Build dependencies: libgflags-dev, libsnappy-dev, zlib1g-dev, libbz2-dev, liblz4-dev, libzstd-dev, liburing-dev

## What to Expect

**When the bug is present (FAIL):**
`DB::Close()` hangs indefinitely; the test program is killed by `timeout` after 60 seconds (exit code 124).

**When the bug is fixed (PASS):**
`DB::Close()` completes normally within seconds.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
