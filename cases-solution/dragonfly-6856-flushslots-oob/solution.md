# Solution: Dragonfly #6856

## Fix PR
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6861
- **Title:** fix(cluster): Validate slot IDs in DFLYCLUSTER FLUSHSLOTS to prevent out-of-bounds crash
- **Commit:** `c79bbe0c646c1bce47f76168dbe813951aecd8ce`

## Root cause
The `DFLYCLUSTER FLUSHSLOTS` command handler accepts slot IDs from user input
and uses them directly as indices into a `std::bitset<16384>`. When a slot ID
>= 16384 is provided, `bitset::set()` throws `std::out_of_range`, which is
caught by the top-level exception handler and causes SIGABRT.

## Fix description
Add input validation before using slot IDs as bitset indices. Specifically,
check that each provided slot ID is in the range [0, 16383] before calling
`bitset::set()`. If an invalid slot ID is found, return an error response
to the client instead of crashing.

## Files changed
- `src/server/cluster/cluster_family.cc` — Added bounds check in the
  FLUSHSLOTS command handler:
  ```cpp
  // Before (buggy):
  for (auto slot : slots) {
      slots_to_flush.set(slot);  // crashes if slot >= 16384
  }

  // After (fixed):
  for (auto slot : slots) {
      if (slot >= ClusterConfig::kMaxSlotNum) {
          return cntx->SendError("Invalid slot id");
      }
      slots_to_flush.set(slot);
  }
  ```

## How to apply the fix
```bash
git checkout c79bbe0c646c1bce47f76168dbe813951aecd8ce
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
