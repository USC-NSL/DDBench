# Kvrocks #3315: ZDIFF with numkeys=0 Causes Process Crash

| Field | Value |
|-------|-------|
| Project | [Kvrocks](https://github.com/apache/kvrocks) |
| Issue | [#3315](https://github.com/apache/kvrocks/issues/3315) |
| Language | C++ |
| Category | Crash (out-of-bounds access) |

## Bug Summary

Sending `ZDIFF 0 a` (with `numkeys=0`) to Kvrocks causes the server process to crash due to an out-of-bounds array access when the number of keys is zero. All client connections are dropped.

## Quick Start

```bash
# from the repository root
./bench.sh setup kvrocks-3315-zdiff-crash        # build image + case repository, warm caches
./bench.sh reproduce kvrocks-3315-zdiff-crash    # FAIL (exit 1) while the bug is present
./bench.sh shell kvrocks-3315-zdiff-crash        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/kvrocks` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Kvrocks process crashes immediately upon receiving `ZDIFF 0 a`.

**When the bug is fixed (PASS):**
The command returns an error response (e.g., "at least 1 input key is needed") and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
