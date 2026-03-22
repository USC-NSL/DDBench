# Solution: Dragonfly #6825

## Fix PR
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6853
- **Title:** fix(cluster): Handle number overflow in DFLYCLUSTER CONFIG parsing
- **Commit:** `4b16da4d2e80eafc57ecb5fef511a9d49afe5c54`

## Root cause
The DFLYCLUSTER CONFIG command parses numeric values from user input without
checking for integer overflow. When very large numbers are provided, the
parsed value overflows, leading to unexpected state and an assertion failure
in the reply guard.

## Fix
Add overflow checks when parsing numeric values in cluster config. Return
an error to the client if values exceed valid ranges instead of proceeding
with overflowed values.

## How to apply
```bash
git checkout 4b16da4d2e80eafc57ecb5fef511a9d49afe5c54
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
