# Solution: Kvrocks #3148

- **Issue:** https://github.com/apache/kvrocks/issues/3148
- **Fix commit:** [`833ae36aa1d17e87be494724689b87e5234286ec`](https://github.com/apache/kvrocks/commit/833ae36aa1d17e87be494724689b87e5234286ec)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/apache/kvrocks/pull/3149
- **Commit:** `833ae36aa1d17e87be494724689b87e5234286ec`

## Root cause
The namespace token management uses a reverse mapping from token to namespace name. When `NAMESPACE SET ns1 token2` is called, it updates ns1's token to `token2` and creates a new reverse mapping `token2 -> ns1`. However, it also deletes the old reverse mapping for `token2`, which was `token2 -> ns2`. This effectively orphans `ns2` — the forward mapping for `ns2` may still exist, but the reverse mapping is gone, and the namespace becomes invisible to `NAMESPACE GET`.

## Fix description
Check for token collision before updating: if the new token is already in use by a different namespace, return an error instead of proceeding with the update. This prevents the deletion of the existing namespace's reverse mapping.

## Key files
- Namespace management code handling the SET operation

## How to apply
```bash
git checkout 833ae36aa1d17e87be494724689b87e5234286ec
git submodule update --init --recursive
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```
