# Symptom

After removing a node from a Raft cluster via configuration change, a pending ReadIndex request that was issued before the removal hangs and does not return promptly. It eventually completes on its own after a delay, but the read should have been satisfiable immediately after the cluster membership shrank.

## Observable behavior
- A ReadIndex request is sent to the leader of a 2-node cluster.
- One peer becomes unresponsive (its response is lost or delayed).
- The unresponsive peer is removed via `remove_node`, shrinking the cluster to 1 node.
- Despite the leader now being the sole member, the pending read does not complete.
- The read only completes after an additional delay (on the order of a heartbeat interval), causing unnecessary latency.
