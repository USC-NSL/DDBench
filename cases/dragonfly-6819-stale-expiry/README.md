# Dragonfly #6819: Stale Expiry After SORT STORE Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6819](https://github.com/dragonflydb/dragonfly/issues/6819) |
| Language | C++ |
| Category | Crash (assertion failure) |

## Bug Summary

When a key is set with an expiry (`SET key val PX 500`) and then overwritten via `SORT key STORE key`, the stale expiry entry is not cleared. When the original expiry time arrives, the expiry cycle attempts to expire the key, leading to a crash at `db_slice.cc:1163`.

## Quick Start

```bash
# from the repository root
./bench.sh setup dragonfly-6819-stale-expiry        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6819-stale-expiry    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6819-stale-expiry        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes when the stale expiry fires after the key has been overwritten by SORT STORE.

**When the bug is fixed (PASS):**
The expiry is properly cleared on overwrite and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
