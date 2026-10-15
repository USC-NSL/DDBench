# Solution: Dragonfly #6764

- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6764
- **Fix commit:** [`01ce1ca9ea6c429e531d6177f72963b1fd29c26d`](https://github.com/dragonflydb/dragonfly/commit/01ce1ca9ea6c429e531d6177f72963b1fd29c26d)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6772
- **Commit:** `01ce1ca9ea6c429e531d6177f72963b1fd29c26d`

## Root cause
HINCRBYFLOAT does not check if the result of the increment is NaN or Infinity. The resulting invalid value creates an inconsistent hash object state.

## Fix description
Check for NaN/Inf results after the increment operation. If the result is non-finite, return an error ("ERR increment would produce NaN or Infinity") instead of storing the value.

## How to apply
```bash
git checkout 01ce1ca9ea6c429e531d6177f72963b1fd29c26d
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
