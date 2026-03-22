# Solution: etcd #20269

## Fix
- **Issue:** https://github.com/etcd-io/etcd/issues/20269

## Root cause
When a member is removed from the cluster, has its data directory deleted, and is re-added, it starts with an empty raft log where `lastIndex=0`. The leader, however, sends heartbeats with a `commit` index reflecting the current cluster state (e.g., commit=150). The raft library's `commitTo` function panics when `commit > lastIndex`:

```go
// In raft/log.go
func (l *raftLog) commitTo(tocommit uint64) {
    if tocommit > l.lastIndex() {
        // This panic fires for the re-added member
        panic(fmt.Sprintf("tocommit(%d) is out of range [lastIndex(%d)]", tocommit, l.lastIndex()))
    }
    ...
}
```

The re-added member has no log entries, but the leader assumes it can commit up to the cluster's current index.

## Fix description
Handle the case where a re-added member receives a heartbeat or append entries with a commit index beyond its current log. Instead of panicking, the member should:

1. Clamp the commit index to `min(tocommit, lastIndex)` when processing heartbeats, OR
2. Detect that it needs a snapshot from the leader (since its log is empty) and request one, OR
3. The leader should detect the follower's empty state and send a snapshot instead of heartbeat with high commit.

The fix is in the raft library's log handling, specifically in `raft/log.go` and potentially `raft/raft.go` where messages from the leader are processed.

## How to apply
```bash
# Identify and checkout the fix commit
git log --oneline --all --grep="20269" | head -5
git checkout <fix-commit-hash>
make build
```
