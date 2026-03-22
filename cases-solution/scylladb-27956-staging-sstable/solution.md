# Solution: ScyllaDB #27956

## Fix
- **Issue:** https://github.com/scylladb/scylladb/issues/27956
- **Buggy commit:** `5d1f74b86ac6ef151871ee300f8728` (regression)

## Root cause
A code change (commit `5d1f74b86ac6ef151871ee300f8728`) moved the view update generator initialization to occur **before** SSTable loading during node startup. The view update generator's initialization routine scans for staging SSTables — SSTables that are in the "staging" directory and need to have their corresponding view updates applied.

The problem with the new ordering:
1. View update generator initializes and scans for staging SSTables → finds none (SSTables not loaded yet)
2. SSTables are loaded from disk, including staging SSTables
3. View update generator never re-scans → staging SSTables are permanently ignored
4. Data in staging SSTables is never applied to materialized views
5. Permanent base-view inconsistency

Before the regression, SSTables were loaded first, then the view update generator was initialized, so it correctly found and processed staging SSTables.

## Fix description
There are two possible approaches:

**Option A (revert ordering):** Move SSTable loading back to before view update generator initialization, restoring the original order. This ensures staging SSTables are present on disk and loaded into memory when the view update generator scans for them.

**Option B (re-scan):** Have the view update generator re-scan for staging SSTables after SSTable loading completes. This allows the initialization order to remain as-is but adds a second discovery pass.

The fix ensures that the view update generator discovers and processes all staging SSTables regardless of initialization order.

Key files:
- The startup/initialization sequence, likely in `main.cc` or `database.cc`
- The view update generator code, likely in `db/view/view_update_generator.cc`

## How to apply
```bash
# Find the fix commit from the issue
git log --oneline --all --grep="27956" | head -5
git checkout <fix-commit-hash>
git submodule update --init --recursive
./configure.py --mode=dev
ninja build/dev/scylla
```
