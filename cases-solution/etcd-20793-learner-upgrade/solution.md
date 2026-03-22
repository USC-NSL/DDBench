# Solution: etcd #20793

## Fix
- **PR:** https://github.com/etcd-io/etcd/pull/20797
- **Commit:** `2e24a9845a3cd24fb52d676670e66c697f34336d`

## Root cause
When a learner member is promoted to a voter in etcd 3.5.x, the promotion is recorded in the raft log and applied to the in-memory membership state. However, the promotion is not properly persisted into the v3store (the backend key-value store used by etcd).

During rolling upgrades, snapshots from older version nodes propagate the stale learner state. In etcd 3.5.x, this is not a problem because membership is primarily tracked in memory and rebuilt from the raft log. However, in etcd 3.6.x, the v3store becomes the authoritative source of truth for membership information.

When upgrading from 3.5.x to 3.6.x:
1. The v3store contains stale data showing the member as a learner
2. etcd 3.6.x reads the v3store and sees the promoted member as still being a learner
3. If the cluster already has learners, the "too many learner members" check triggers
4. The node refuses to start, blocking the upgrade

## Fix description
The fix ensures that learner promotion events are correctly persisted into the v3store during rolling upgrades. When a learner is promoted to a voter, the v3store membership entry is updated to reflect the new role. This ensures that when etcd 3.6.x reads the v3store as the source of truth, it sees the correct membership state.

## How to apply
```bash
git checkout 2e24a9845a3cd24fb52d676670e66c697f34336d
make build
```
