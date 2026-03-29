# Symptom

After a Consul server in a secondary datacenter loses leadership and immediately regains it (the same server wins the next election), ACL token, policy, and role replication from the primary DC stops permanently and never recovers on its own.

## Observable behavior

- New ACL tokens, policies, and roles created in the primary datacenter are **not replicated** to the secondary datacenter after the re-election event. Queries to the secondary DC return the stale ACL state from before the leadership disruption.
- The condition triggers specifically when the **same server** loses and regains leadership in quick succession (e.g., due to a brief network partition or a slow heartbeat round). If a different server becomes the new leader, the bug does not trigger.
- The secondary DC's server logs show the `acl token replication`, `acl policy replication`, and `acl role replication` routine **stop messages** during the leadership-loss phase, but corresponding **start messages** are absent when the same server re-establishes leadership — the replication routines are never restarted.
- The server does not crash. All other leader functions (KV, catalog, session timers) work normally. Only ACL replication is silently dead.
- The affected server's Raft log index and commit index remain consistent with the rest of the cluster; there is no election anomaly visible at the Raft level.
- The bug persists until the next leadership change. Restarting the affected server or triggering another election (to a different leader) resolves it.
- The bug was observed across multiple Consul versions (1.9.x, 1.10.x) and was triggered more frequently after 1.10 introduced changes that made brief lose/regain leadership cycles more common.
