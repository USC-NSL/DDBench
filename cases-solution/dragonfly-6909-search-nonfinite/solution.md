# Solution: Dragonfly #6909

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6911
- **Commit:** `1c38bb63d2824080430d6d25e5a6fe6d714a2882`

## Root cause
Two issues:
1. No validation that NUMERIC values are finite (not NaN, Inf, -Inf) before inserting them into the search index. Non-finite values cause undefined behavior in the index data structures.
2. The `KeepTopKSorted` function can access elements out-of-bounds when the result set size is smaller than expected.

## Fix description
1. Add validation to reject non-finite numeric values during indexing, returning an error instead of crashing.
2. Add bounds checking in `KeepTopKSorted` to prevent out-of-bounds access.

## How to apply
```bash
git checkout 1c38bb63d2824080430d6d25e5a6fe6d714a2882
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
