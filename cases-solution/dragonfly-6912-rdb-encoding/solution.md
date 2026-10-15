# Solution: Dragonfly #6912

- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6912
- **Fix commit:** [`ef296f099b6e210ad28f043be9d0a8cec4dc4885`](https://github.com/dragonflydb/dragonfly/commit/ef296f099b6e210ad28f043be9d0a8cec4dc4885)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **Commit:** `ef296f099b6e210ad28f043be9d0a8cec4dc4885`

## Root cause
The `RdbObjectType` function in `rdb_save.cc` does not handle the CMS (Count-Min Sketch) type. When `DUMP` or any RDB serialization path encounters a key with type 17 (CMS), it falls through to a fatal error: `Unknown encoding 0 for type 17`.

## Fix description
Add CMS type handling in the `RdbObjectType` function in `rdb_save.cc`. Map the CMS internal type to an appropriate RDB type code so that serialization can proceed correctly.

## Key files
- `src/server/rdb_save.cc` — `RdbObjectType` function

## How to apply
```bash
git checkout ef296f099b6e210ad28f043be9d0a8cec4dc4885
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
