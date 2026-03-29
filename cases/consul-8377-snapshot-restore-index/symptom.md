# Symptom

After a Consul cluster restarts from Raft snapshots, stale queries to follower servers return different `CreateIndex` and `ModifyIndex` values for the same nodes, services, and health checks compared to the leader. This causes blocking queries to return stale data and CAS (check-and-set) updates applied via the leader to not be reflected on followers.

## Observable behavior
- Each server in the cluster reports different `CreateIndex`/`ModifyIndex` values for the same health check or service when queried with `?stale`. Consistent (leader-forwarded) queries return correct values.
- The inconsistency affects all catalog entries (nodes, services, checks) that existed before the restart, not just a single entry. All affected entries share the same per-server `CreateIndex` value, suggesting a systematic issue during restoration.
- Newly registered services after the restart are not affected — only entries that were restored from snapshots.
- The issue is permanent: followers never self-correct. De-registering and re-registering an affected service resolves it for that entry.
- No error messages appear in any server's logs. The Raft applied index and commit index are consistent across all servers.
- The bug is triggered when servers take snapshots at different Raft log indexes (normal behavior) and then all restart, each restoring from its own local snapshot.
