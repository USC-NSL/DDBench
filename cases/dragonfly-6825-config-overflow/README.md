# Dragonfly #6825: DFLYCLUSTER CONFIG with Overflow Value Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6825](https://github.com/dragonflydb/dragonfly/issues/6825) |
| Language | C++ |
| Category | Crash (SIGABRT / assertion failure) |

## Bug Summary

When running Dragonfly in cluster mode, sending a `DFLYCLUSTER CONFIG` command with values that cause integer overflow during parsing results in an assertion failure (`Check failed: rb->RepliesRecorded() > replies_recorded_`) and process crash with SIGABRT.

## Quick Start

```bash
# from the repository root
./bench.sh setup dragonfly-6825-config-overflow        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6825-config-overflow    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6825-config-overflow        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes with SIGABRT (exit code 134) when DFLYCLUSTER CONFIG receives an overflow value.

**When the bug is fixed (PASS):**
The command returns an error response and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
