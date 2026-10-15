# Dragonfly #6619: EVALSHA with Empty SHA Causes Assertion Failure

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6619](https://github.com/dragonflydb/dragonfly/issues/6619) |
| Language | C++ |
| Category | Crash (SIGABRT / assertion failure) |

## Bug Summary

Sending `EVALSHA "" 0` (with an empty SHA string) causes the Dragonfly process to crash with an assertion failure (`Check failed: !eval_args.sha.empty()`). The empty SHA is not validated before being used.

## Quick Start

```bash
# from the repository root
./bench.sh setup dragonfly-6619-evalsha-empty        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6619-evalsha-empty    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6619-evalsha-empty        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes with SIGABRT (exit code 134) immediately upon receiving `EVALSHA "" 0`.

**When the bug is fixed (PASS):**
The command returns an error response and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
