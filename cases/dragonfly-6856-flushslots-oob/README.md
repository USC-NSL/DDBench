# Dragonfly #6856: DFLYCLUSTER FLUSHSLOTS with OOB Slot ID Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6856](https://github.com/dragonflydb/dragonfly/issues/6856) |
| Language | C++ |
| Category | Crash (SIGABRT / out-of-bounds) |

## Bug Summary

When running Dragonfly in cluster mode, sending `DFLYCLUSTER FLUSHSLOTS 16384` (or any slot ID >= 16384) causes the process to crash with SIGABRT. The slot ID exceeds the valid range (0-16383) and triggers an out-of-bounds bitset access: `bitset::set: __position (which is 16384) >= _Nb (which is 16384)`.

## Quick Start

```bash
# from the repository root
./bench.sh setup dragonfly-6856-flushslots-oob        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6856-flushslots-oob    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6856-flushslots-oob        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes with SIGABRT (exit code 134) when FLUSHSLOTS receives an out-of-range slot ID.

**When the bug is fixed (PASS):**
The command returns an error response and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
