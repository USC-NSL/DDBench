# Kvrocks #3339: XREADGROUP BLOCK Sends Double Response

| Field | Value |
|-------|-------|
| Project | [Kvrocks](https://github.com/apache/kvrocks) |
| Issue | [#3339](https://github.com/apache/kvrocks/issues/3339) |
| Language | C++ |
| Category | Protocol Violation (double RESP response) |

## Bug Summary

Under concurrent load, `XREADGROUP GROUP ... BLOCK` sends two responses for a single command: first an empty array (`*-1\r\n`), then the actual stream entry when new data arrives via `XADD`. This violates the Redis protocol (one response per command) and causes client-side protocol desynchronization.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- C++ compiler (GCC 7+ or Clang)
- CMake 3.16+
- `redis-cli` (from redis-tools package)
- Python 3 with `redis` package (for detection script)

## What to Expect

**When the bug is present (FAIL):**
The raw socket reader detects double RESP responses (`*-1\r\n` followed by another response for the same command), or the Python-based consumer encounters protocol errors due to desynchronization.

**When the bug is fixed (PASS):**
Each `XREADGROUP` command receives exactly one response with no protocol errors.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
