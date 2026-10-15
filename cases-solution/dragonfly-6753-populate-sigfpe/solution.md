# Solution: Dragonfly #6753

- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6753
- **Fix commit:** [`5e31c9f84acfcfc2a7fb421cde7845ffcdf5536e`](https://github.com/dragonflydb/dragonfly/commit/5e31c9f84acfcfc2a7fb421cde7845ffcdf5536e)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6754
- **Commit:** `5e31c9f84acfcfc2a7fb421cde7845ffcdf5536e`

## Root cause
`DoPopulateBatch()` uses `val_size` as a divisor without checking for zero.
When `val_size=0`, a division by zero occurs, resulting in SIGFPE.

## Fix description
Add a validation check at the beginning of the DEBUG POPULATE handler:
if `val_size` is 0, return an error to the client instead of proceeding.

## How to apply
```bash
git checkout 5e31c9f84acfcfc2a7fb421cde7845ffcdf5536e
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
