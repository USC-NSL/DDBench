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
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- C++ compiler (GCC 11+ or Clang 14+)
- CMake 3.16+
- Ninja build system
- `redis-cli` (from redis-tools package)
- `nc` (netcat)
- Python 3

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes with SIGABRT when a large value is retrieved via memcached meta get.

**When the bug is fixed (PASS):**
The meta get command returns the value successfully and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
