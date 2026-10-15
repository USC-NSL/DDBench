# Dragonfly #6654: Memcached Meta Get on Large Value Causes Assertion Failure

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6654](https://github.com/dragonflydb/dragonfly/issues/6654) |
| Language | C++ |
| Category | Crash (SIGABRT / buffer overflow assertion) |

## Bug Summary

When using the memcached protocol with meta get commands, retrieving a large value (8000+ bytes) causes a crash. The reply builder's `expected_buffer_cap` exceeds the `kMaxBufferSize` constant (8192 bytes), triggering a fatal assertion. This only occurs with the memcached protocol, not with the Redis protocol.

## Quick Start

```bash
# from the repository root
./bench.sh setup dragonfly-6654-mc-reply-large        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6654-mc-reply-large    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6654-mc-reply-large        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes with SIGABRT when a large value is retrieved via memcached meta get.

**When the bug is fixed (PASS):**
The meta get command returns the value successfully and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
