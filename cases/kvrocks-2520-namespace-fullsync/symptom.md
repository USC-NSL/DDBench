# Symptom

After a replica performs `SLAVEOF` from a master that has multiple namespaces configured, only the `__namespace` (default) namespace is visible on the replica. The additional namespaces (e.g., `ns1`, `ns2`) are not accessible via `NAMESPACE GET *` on the replica, even though the full sync completed successfully.

## Observable behavior

- Master has namespaces `ns1` and `ns2` configured with respective tokens.
- Slave executes `SLAVEOF <master-ip> <master-port>` and the full sync completes (master_link_status shows "up").
- Running `NAMESPACE GET *` on the slave returns only the default namespace.
- Data written under those namespaces on the master is present in the slave's underlying storage (can be confirmed by restarting the slave process).
- Restarting the slave without any other changes makes all namespaces visible again.
- The issue occurs every time a full sync is performed; it is 100% reproducible.
