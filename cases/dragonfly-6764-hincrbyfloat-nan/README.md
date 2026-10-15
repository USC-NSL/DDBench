# Dragonfly #6764: HINCRBYFLOAT with NaN/Inf Causes Crash

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6764](https://github.com/dragonflydb/dragonfly/issues/6764) |
| Language | C++ |
| Category | Crash (assertion failure) |

## Bug Summary

Running `HINCRBYFLOAT` with `nan` as the increment on a nonexistent hash field creates an invalid internal state. A subsequent `HRANDFIELD` on the same hash triggers a crash at `hset_family.cc:973` because the hash is left in an invalid empty state.

## Quick Start

```bash
# from the repository root
./bench.sh setup dragonfly-6764-hincrbyfloat-nan        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6764-hincrbyfloat-nan    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6764-hincrbyfloat-nan        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The Dragonfly process crashes when HRANDFIELD is called on a hash corrupted by HINCRBYFLOAT with nan.

**When the bug is fixed (PASS):**
The HINCRBYFLOAT command returns an error for non-finite values and the process remains alive.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
