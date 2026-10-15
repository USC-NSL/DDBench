# Dragonfly #6753: DEBUG POPULATE with val_size=0 Causes SIGFPE

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6753](https://github.com/dragonflydb/dragonfly/issues/6753) |
| Language | C++ |
| Category | Crash (SIGFPE / division by zero) |

## Bug Summary

Running `DEBUG POPULATE 100 prefix 0` (with `val_size=0`) causes the Dragonfly process to crash with SIGFPE. The `DoPopulateBatch()` function in `DebugCmd` performs a division by `val_size` without checking for zero.

## Quick Start

```bash
# from the repository root
./bench.sh setup dragonfly-6753-populate-sigfpe        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6753-populate-sigfpe    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6753-populate-sigfpe        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes with SIGFPE (exit code 136) immediately upon receiving `DEBUG POPULATE 100 prefix 0`.

**When the bug is fixed (PASS):**
The command returns an error response and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
