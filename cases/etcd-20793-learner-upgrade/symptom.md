# Symptom

During a multi-step rolling upgrade of an etcd cluster (3.5.19 -> 3.5.21 -> 3.6.x), a cluster that previously had a learner member that was promoted to voter fails to complete the final upgrade.

The error during the final upgrade attempt is:
```
too many learner members in cluster
```

This occurs because the learner promotion state is not correctly persisted into the v3store. During rolling upgrades, snapshots from older versions propagate stale learner membership information. When etcd 3.6.x switches to using v3store as the source of truth for membership, it sees the member as still being a learner even though it was promoted long ago.

The cluster operates normally on 3.5.x, and the issue only manifests when upgrading to 3.6.x where the membership source of truth changes.
