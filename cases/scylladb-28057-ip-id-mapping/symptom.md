# Symptom: ScyllaDB #28057

When a node replace operation fails during the streaming phase, and all remaining live nodes are then shut down before the failed replacing node can roll back, restarting the cluster causes errors in `nodetool status` and cluster operations.

The issue is that the raft topology's IP-to-ID mapping for the replacing node is not preserved across restarts. The IP preservation logic only handles bootstrapping nodes, not replacing nodes. After restart, the cluster cannot properly identify the replacing node's state, leading to:

1. `nodetool status` errors — unable to resolve node identity
2. Topology operations may hang or fail
3. The cluster may not fully come up if it cannot resolve the replacing node's membership state

The problem only manifests when:
- A node replace is initiated
- The replace fails during streaming (not during other phases)
- All live nodes are shut down before the replace operation can roll back
- The cluster is then restarted
