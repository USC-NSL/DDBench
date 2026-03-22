# Solution: Dragonfly #6766

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6785
- **Commit:** `f3ee1ad3ef1bd6c5bbdb2e26b1c380e324602fed`

## Root cause
JSON nested updates (e.g., `JSON.SET` on a sub-path) can leave orphaned objects when updating nested structures. When a nested value is replaced, the old value's sub-objects are not properly freed, leading to memory tracking corruption. When the key is eventually deleted, the memory accounting is inconsistent, triggering an assertion failure at `json_family.cc:99`.

## Fix description
Fix memory tracking in the JSON family to properly clean up orphaned objects during nested updates. Ensure that when a sub-path is updated, all replaced objects are properly accounted for in the memory tracking system.

## How to apply
```bash
git checkout f3ee1ad3ef1bd6c5bbdb2e26b1c380e324602fed
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
