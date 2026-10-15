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
# from the repository root
./bench.sh setup rocksdb-10751-stalled-writes-shutdown        # build image + case repository, warm caches
./bench.sh reproduce rocksdb-10751-stalled-writes-shutdown    # FAIL (exit 1) while the bug is present
./bench.sh shell rocksdb-10751-stalled-writes-shutdown        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/rocksdb` image; see the top-level README).

## Build Notes

- Release build of the static library only (`build/librocksdb.a`, tests disabled); the oracle compiles `test_stall_shutdown.cc` from the case directory against it.

## What to Expect

**When the bug is present (FAIL):**
`DB::Close()` hangs indefinitely; the test program is killed by `timeout` after 60 seconds (exit code 124).

**When the bug is fixed (PASS):**
`DB::Close()` completes normally within seconds.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
