# Solution: etcd #20704

- **Issue:** https://github.com/etcd-io/etcd/issues/20704
- **Fix commit:** none — No upstream fix (the issue was closed as not planned); gold.patch was written for this benchmark.
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **Issue:** https://github.com/etcd-io/etcd/issues/20704
- **Status:** No upstream fix. The issue was closed as "not planned" (stale bot, 2025-11-30).
- **Buggy commit:** `f0c0ca05c102203e17da685c8375fdafc37ed4d5` (main, 2026-04-13). The case used to track
  `main`; it is now pinned. `client/v3/leasing` is byte-identical at every main commit the April 2026 agent
  runs were built at, and unchanged since 2024-10.
- **Gold patch (NOT upstream):** `gold.patch` in this directory. It was written for this benchmark, in
  `client/v3/leasing/cache.go`. It is the minimal change that removes the Delete+Put race checked by the
  oracle. It does not redesign the `waitc` mechanism, so the Put+Get and Put+Put+Get races below are not
  addressed. The oracle checks only the Delete+Put race.

## Root cause
The `waitc` channel mechanism in `client/v3/leasing` for detecting concurrent modifications is fundamentally flawed. The mechanism uses a channel to signal that a concurrent operation has started, but there are multiple race windows:

1. **Delete + Put:** When a `Delete` and `Put` run concurrently on the same key, the cache can end up in a state where the key is marked as deleted but actually has a value on the server (or vice versa).
2. **Put + Get:** A `Get` can observe a stale value because `NotifyOps` reports no concurrent `waitc` channels, but a `Put` starts immediately after, before the `RLock` is acquired.
3. **Put + Put + Get:** Two concurrent `Put` operations can result in the cache storing a `Version` that corresponds to neither put.

## Fix description
The concurrency control mechanism in the leasing cache needs to be redesigned. The `waitc` channel approach cannot provide linearizability because there is always a window between checking for concurrent operations and acquiring the lock. A proper fix would need to use a serialization mechanism that atomically checks and applies cache updates.

## Gold patch (what it changes)
`leaseCache.Update()` (applied after a successful Put) now ignores a Put whose revision is older than the
revision already reflected in the cached response. Without that check, when a concurrent Delete's cache
update is applied first, the later-applied Put update recreates the key in the cache (`len(Kvs) == 0`
branch). The cache then reports a key that etcd has deleted.

## Key files
- `client/v3/leasing/cache.go` — `NotifyOps`, `waitc` mechanism
- `client/v3/leasing/txn.go` — `txnLeasing.eval`
- `client/v3/leasing/kv.go` — `Put`, `Delete`, `Get` methods
