# Code Investigation

## What was searched
The symptom describes different `CreateIndex`/`ModifyIndex` values across servers after restoring from snapshots. A developer would trace the snapshot restore path to see how catalog entries (nodes, services, checks) are re-created and whether their original index values are preserved.

## What was found

The snapshot restore path passes the snapshot's `LastIndex` as the Raft index for all registration operations:

```go
// agent/consul/fsm/snapshot_oss.go:486-496
func restoreRegistration(header *snapshotHeader, restore *state.Restore, decoder *codec.Decoder) error {
    var req structs.RegisterRequest
    if err := decoder.Decode(&req); err != nil {
        return err
    }
    if err := restore.Registration(header.LastIndex, &req); err != nil {
        return err
    }
    return nil
}
```

`Restore.Registration()` directly calls `ensureRegistrationTxn` with this index:

```go
// agent/consul/state/catalog.go:218-222
func (s *Restore) Registration(idx uint64, req *structs.RegisterRequest) error {
    if err := s.store.ensureRegistrationTxn(s.tx, idx, req); err != nil {
        return err
    }
    return nil
}
```

`ensureRegistrationTxn` constructs a new node struct WITHOUT the original `CreateIndex`/`ModifyIndex`:

```go
// agent/consul/state/catalog.go:259-267
node := &structs.Node{
    ID:              req.ID,
    Node:            req.Node,
    Address:         req.Address,
    Datacenter:      req.Datacenter,
    TaggedAddresses: req.TaggedAddresses,
    Meta:            req.NodeMeta,
}
// Note: CreateIndex and ModifyIndex are NOT copied from req
```

Then `ensureNodeTxn` assigns indexes based on the passed `idx` parameter:

```go
// agent/consul/state/catalog.go:456-459
} else {
    node.CreateIndex = idx    // idx = header.LastIndex from the snapshot
    node.ModifyIndex = idx
}
```

Since the restore starts with an empty state store, the `n == nil` branch (line 458-459) is always taken during restore. The node's `CreateIndex` and `ModifyIndex` are both set to `header.LastIndex` — the Raft index at which the snapshot was taken.

The same pattern applies to services (line 806-808) and health checks (line 1605-1606, 1680) in the same file.

## Developer hypothesis
The `restoreRegistration` function's handling of index values during snapshot restore.
