# Solution: etcd #20704

## Fix
- **Issue:** https://github.com/etcd-io/etcd/issues/20704
- **Status:** Open (fix pending)

## Root cause
The `waitc` channel mechanism in `client/v3/leasing` for detecting concurrent modifications is fundamentally flawed. The mechanism uses a channel to signal that a concurrent operation has started, but there are multiple race windows:

1. **Delete + Put:** When a `Delete` and `Put` run concurrently on the same key, the cache can end up in a state where the key is marked as deleted but actually has a value on the server (or vice versa).
2. **Put + Get:** A `Get` can observe a stale value because `NotifyOps` reports no concurrent `waitc` channels, but a `Put` starts immediately after, before the `RLock` is acquired.
3. **Put + Put + Get:** Two concurrent `Put` operations can result in the cache storing a `Version` that corresponds to neither put.

## Fix description
The concurrency control mechanism in the leasing cache needs to be redesigned. The `waitc` channel approach cannot provide linearizability because there is always a window between checking for concurrent operations and acquiring the lock. A proper fix would need to use a serialization mechanism that atomically checks and applies cache updates.

## Key files
- `client/v3/leasing/cache.go` — `NotifyOps`, `waitc` mechanism
- `client/v3/leasing/txn.go` — `txnLeasing.eval`
- `client/v3/leasing/kv.go` — `Put`, `Delete`, `Get` methods
