# Solution: Dragonfly #6614

- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6614
- **Fix commit:** [`84034d0903e8409dd48adcce974e5250d357a7ce`](https://github.com/dragonflydb/dragonfly/commit/84034d0903e8409dd48adcce974e5250d357a7ce)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6615
- **Commit:** `84034d0903e8409dd48adcce974e5250d357a7ce`

## Root cause
`ChangeMonitor` is not idempotent. Calling MONITOR twice in a MULTI/EXEC block adds the connection to the monitor list twice, and the destructor asserts that `cc_` is valid.

## Fix description
Make `ChangeMonitor` idempotent — if a connection is already in monitor mode, skip the duplicate add.

## How to apply
```bash
git checkout 84034d0903e8409dd48adcce974e5250d357a7ce
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
