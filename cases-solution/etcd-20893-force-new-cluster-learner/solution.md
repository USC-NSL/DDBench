# Solution: etcd #20893

## Fix
- **PR:** https://github.com/etcd-io/etcd/pull/20894
- **Commit:** `c58e6f1caf7dfe07da002230a2b61d664ab21a34`

## Root cause
In `server/storage/util.go`, lines 121-123, the `forceMembersFromSnap` function only considers voting members when rebuilding the member list from a snapshot. It ignores learners entirely. When `--force-new-cluster` is used, the code iterates over `snap.Membership.Members()` but does not check `snap.Membership.Learners()`, so learner members are preserved in the rebuilt cluster.

## Fix description
Include learners in the member cleanup logic during `--force-new-cluster`. The fix modifies the snapshot processing to also iterate over learners and remove them, ensuring the recovered cluster contains only the single bootstrapping node.

## Key files
- `server/storage/util.go` — the `forceMembersFromSnap` function

## How to apply
```bash
git checkout c58e6f1caf7dfe07da002230a2b61d664ab21a34
make build
```
