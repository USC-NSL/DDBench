# Solution: Dragonfly #6907

- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6907
- **Fix commit:** [`c09a5a16bacc4b107435b0f144c1eb4a7553fd04`](https://github.com/dragonflydb/dragonfly/commit/c09a5a16bacc4b107435b0f144c1eb4a7553fd04)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6908
- **Commit:** `c09a5a16bacc4b107435b0f144c1eb4a7553fd04`

## Root cause
The search code does not validate that VECTOR/NUMERIC field values match the expected size before accessing them, leading to out-of-bounds reads.

## Fix description
Add size validation for vector and numeric field values before accessing them in the search doc accessors. Return empty/error for malformed documents instead of crashing.

## How to apply
```bash
git checkout c09a5a16bacc4b107435b0f144c1eb4a7553fd04
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
