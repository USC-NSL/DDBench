# Solution: ScyllaDB #28057

## Fix
- **PR:** https://github.com/scylladb/scylladb/pull/27435
- **Commit:** `af6cb0d0a431170d32ad7816c050f875298aa840`

## Root cause
The raft topology module preserves IP-to-ID mappings across restarts for nodes that are in the bootstrapping state. This is necessary because when a node is mid-bootstrap and the cluster restarts, the cluster needs to know which IP address corresponds to which raft ID to properly handle the incomplete operation.

However, the same preservation was not implemented for nodes in the **replacing** state. When a replace operation fails during streaming and all nodes are then shut down, on restart:

1. The IP-to-ID mapping for the replacing node is lost
2. The cluster cannot resolve the replacing node's identity
3. Raft topology operations fail because they reference an unknown node ID
4. `nodetool status` cannot display correct information

The code that handles IP preservation during restart only checked for `topology::state::bootstrapping`, missing the `topology::state::replacing` case.

## Fix description
Extend the IP-to-ID mapping preservation logic to also handle nodes in the replacing state. When a node is in the `replacing` state in the raft topology, its IP-to-ID mapping should be preserved across restarts, just like it is for bootstrapping nodes.

The fix adds the replacing state to the IP preservation check:

```cpp
// Before (buggy):
if (node_state == topology::state::bootstrapping) {
    preserve_ip_mapping(node_id, ip);
}

// After (fixed):
if (node_state == topology::state::bootstrapping ||
    node_state == topology::state::replacing) {
    preserve_ip_mapping(node_id, ip);
}
```

Key file: The raft topology coordinator/manager code, likely in `service/raft/raft_group0.cc` or `service/topology_coordinator.cc`.

## How to apply
```bash
git checkout af6cb0d0a431170d32ad7816c050f875298aa840
git submodule update --init --recursive
./configure.py --mode=dev
ninja build/dev/scylla
```
