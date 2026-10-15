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
# from the repository root
./bench.sh setup kvrocks-3339-xreadgroup-double        # build image + case repository, warm caches
./bench.sh reproduce kvrocks-3339-xreadgroup-double    # FAIL (exit 1) while the bug is present
./bench.sh shell kvrocks-3339-xreadgroup-double        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/kvrocks` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The raw socket reader detects double RESP responses (`*-1\r\n` followed by another response for the same command), or the Python-based consumer encounters protocol errors due to desynchronization.

**When the bug is fixed (PASS):**
Each `XREADGROUP` command receives exactly one response with no protocol errors.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
