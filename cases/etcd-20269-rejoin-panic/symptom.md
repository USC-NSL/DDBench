# Symptom

When a member is removed from an etcd cluster, has its data directory wiped (reset), and is then re-added to the cluster, it panics immediately upon receiving a heartbeat from the leader.

The panic message is:
```
panic: tocommit(X) is out of range [lastIndex(0)]. Was the raft log corrupted, truncated, or lost?
```

This happens because the reset member starts with an empty raft log (`lastIndex=0`), but the leader sends a heartbeat containing a high commit index from the existing cluster state. The raft library does not handle this case gracefully — it assumes the commit index should never exceed the last log index, and panics.

The bug affects any scenario where a member is removed, its state is cleared, and it is re-added to a running cluster. This is a common operational pattern for replacing failed members.
