# Solution: etcd #20657

## Fix
- **Issue:** https://github.com/etcd-io/etcd/issues/20657

## Root cause
The snapshot cleanup routine (`Snapshotter.CleanupSnapdir` or equivalent cleanup path) deletes older `.snap.db` files that it considers "orphaned" — i.e., snapshot database files that no longer correspond to the latest snapshot metadata. However, the snapshot application path (`applySnapshot` / `openSnap`) may still be actively reading one of these "orphaned" files. There is no synchronization (lock, reference count, or similar) between cleanup and application.

When `--snapshot-count` is set very low (e.g., 2), snapshots are created and cleaned up at a very high rate. Combined with leader changes that force followers to apply snapshots from the leader, the window for the race is enlarged:

1. Follower starts applying snapshot N by opening `N.snap.db`
2. Snapshot N+1 is created
3. Cleanup runs: sees `N.snap.db` as orphaned (N+1 is current), deletes it
4. Follower's apply path tries to read `N.snap.db` — file not found — panic

## Fix description
Synchronize snapshot cleanup with snapshot application. The fix ensures that the cleanup routine does not delete a `.snap.db` file while it may still be in use by the application path. This can be achieved by:

1. Adding a mutex that is held during snapshot application and checked during cleanup, OR
2. Deferring cleanup of `.snap.db` files until after snapshot application is confirmed complete, OR
3. Using reference counting on snapshot files to prevent deletion while readers exist.

The key files involved are in the `server/etcdserver/api/snap/` package:
- `snapshotter.go` — snapshot save/load/cleanup logic
- The server-side apply path in `server/etcdserver/server.go` or `server/etcdserver/apply.go`

## How to apply
```bash
# Checkout the fix commit (identify from the issue or PR)
git log --oneline --all --grep="20657" | head -5
# Checkout the fix commit
git checkout <fix-commit-hash>
make build
```
