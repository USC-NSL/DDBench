# Solution: hashicorp/raft #291

## Fix
- **PR:** https://github.com/hashicorp/raft/pull/292
- **Commit:** `da92cfe76e0c1c9b94bbc9d884ec4b2b3b90b699`

## Root cause

When `VerifyLeader()` is called, it creates a `verifyFuture` and adds it to `leaderState.notify` map, keyed by a verify counter. It also adds the future to each replication goroutine's `repl.notify` map (one per follower).

When AppendEntries to a follower fails (because the follower is disconnected), the replication goroutine handles the error but does **not** clean up the future from `repl.notify`. Meanwhile, the leader eventually resolves and deletes the future from `leaderState.notify`.

The result is that `repl.notify` accumulates stale futures that are never cleaned up:
- `leaderState.notify[v]` is deleted when the future completes.
- `repl.notify[v]` is NOT deleted when AppendEntries returns an error.
- The `verifyFuture` objects referenced by `repl.notify` entries are kept alive by the reference, preventing garbage collection.

Over many VerifyLeader calls with a failed follower, `repl.notify` grows without bound.

## Fix description

Clean up verifyLeader futures from `replState.notify` when they are completed. When a verify future is resolved (either successfully or due to timeout/error), remove it from all `repl.notify` maps:

```go
// When completing a verify future, also clean up from repl.notify
for _, repl := range r.leaderState.replState {
    delete(repl.notify, v)
}
```

This ensures that stale futures do not accumulate in `repl.notify` when followers are unreachable.

## How to apply
```bash
git checkout da92cfe76e0c1c9b94bbc9d884ec4b2b3b90b699
go mod download
go test -v -run TestVerifyLeaderOOM -timeout 120s
```

## How to verify
Run 10,000+ VerifyLeader calls with a disconnected follower. Memory usage should remain stable (under 10MB growth) instead of growing linearly with call count.
