# Solution: Kvrocks #3315

- **Issue:** https://github.com/apache/kvrocks/issues/3315
- **Fix commit:** [`c2c5d094d4335c4951f88e7de319d78e1bf5b3b8`](https://github.com/apache/kvrocks/commit/c2c5d094d4335c4951f88e7de319d78e1bf5b3b8)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/apache/kvrocks/pull/3316
- **Commit:** `c2c5d094d4335c4951f88e7de319d78e1bf5b3b8`

## Root cause
The ZDIFF command handler does not check if `numkeys` is 0. With numkeys=0,
the code attempts to access `keys[0]` which is out of bounds, causing a crash.

## Fix description
Add a check in the ZDIFF command parser: if numkeys <= 0, return an error
response to the client ("ERR at least 1 input key is needed for ZDIFF").

## How to apply
```bash
git checkout c2c5d094d4335c4951f88e7de319d78e1bf5b3b8
mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Debug && make -j$(nproc)
```
