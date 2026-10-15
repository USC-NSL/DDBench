# Solution: Dragonfly #6819

- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6819
- **Fix commit:** [`fa4d116313779182571f70a537ab31f09ec043a5`](https://github.com/dragonflydb/dragonfly/commit/fa4d116313779182571f70a537ab31f09ec043a5)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6821
- **Commit:** `fa4d116313779182571f70a537ab31f09ec043a5`

## Root cause
`AddOrUpdateInternal` does not clear the expiry entry when overwriting an existing key that had a TTL with a new value that has no TTL. The old expiry remains in the expiry data structure, and when the expiry cycle fires, it attempts to expire a key that no longer has a TTL set, causing a crash at `db_slice.cc:1163`.

## Fix description
Clear the stale expiry entry in `AddOrUpdateInternal` when the new value has no expiration. When a key is being overwritten and the new value does not specify a TTL, any existing expiry entry for that key must be removed.

## Key files
- `src/server/db_slice.cc` — `AddOrUpdateInternal` method

## How to apply
```bash
git checkout fa4d116313779182571f70a537ab31f09ec043a5
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
