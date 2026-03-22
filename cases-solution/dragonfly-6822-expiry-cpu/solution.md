# Solution: Dragonfly #6822

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6846
- **Commit:** `4df1a91450cd504c37bff5730944a3569996abff`

## Root cause

The `DeleteExpiredStep` function in Dragonfly's expiry subsystem traverses the DashTable to find and delete expired keys. When a large number of keys expire simultaneously, this traversal runs in a tight loop without yielding control back to the event loop.

Because Seastar/Helio uses cooperative scheduling, this long-running loop starves all other fibers on the same thread, including:
- Client request handling (PING, GET, SET, etc.)
- Heartbeat / health checks
- Replication

The result is that the entire server becomes unresponsive for the duration of the expiry sweep.

## Fix description

The fix adds yield points during the DashTable traversal in `DeleteExpiredStep`. After processing a batch of expired entries, the function yields to the event loop (via `FiberYield()` or equivalent), allowing other tasks to run.

Key changes:
- In the expiry traversal loop, after every N deletions (or after a time threshold), call `FiberYield()` to give other fibers a chance to run.
- This breaks the long-running expiry sweep into smaller chunks, keeping the server responsive.

## How to apply
```bash
git checkout 4df1a91450cd504c37bff5730944a3569996abff
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Release
```

## How to verify
Load 600k keys with short TTL, wait for expiry, and verify PING responds within milliseconds throughout the expiry cycle.
