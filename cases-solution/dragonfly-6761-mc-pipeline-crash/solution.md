# Solution: Dragonfly #6761

- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6761
- **Fix commit:** [`5a78b758ff21f179963de4da9e7ad301459e23bb`](https://github.com/dragonflydb/dragonfly/commit/5a78b758ff21f179963de4da9e7ad301459e23bb)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6762
- **Commit:** `5a78b758ff21f179963de4da9e7ad301459e23bb`

## Root cause
STATS and VERSION commands return `WOULD_BLOCK` in memcache pipeline mode. The pipeline processor does not handle this return value, leading to a crash.

## Fix description
Return `WOULD_BLOCK` status properly for STATS/VERSION in MC pipeline context. The fix ensures these commands are handled correctly when pipelined.

## How to apply
```bash
git checkout 5a78b758ff21f179963de4da9e7ad301459e23bb
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
