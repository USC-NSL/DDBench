# Verification: Consul #8377

```bash
# Run the FSM snapshot restore test that checks index preservation.
# The test creates an FSM, registers entries, snapshots, restores,
# then asserts CreateIndex/ModifyIndex are preserved across the restore.

cd agent/consul/fsm
go test -run TestFSM_SnapshotRestore_IndexPreservation -v -count=1 -timeout 60s ./...
```

- **FAIL:** The injected test fails because `CreateIndex`/`ModifyIndex` values after snapshot restore do not match the values before the snapshot. Each server assigns its own restore index instead of preserving the original.
- **PASS:** The test passes because the snapshot restore correctly preserves the original `CreateIndex`/`ModifyIndex` values for nodes, services, and health checks.
