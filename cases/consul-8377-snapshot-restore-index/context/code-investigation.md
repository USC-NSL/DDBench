# Code Investigation

## What was searched
The symptom describes servers reporting different `CreateIndex`/`ModifyIndex` values for the same catalog entries after all servers restart from their local snapshots. Traced how catalog registrations are re-created by the FSM snapshot restore code.

## What was found
```
$ sed -n "486,496p" agent/consul/fsm/snapshot_oss.go
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

```
$ sed -n "215,244p" agent/consul/state/catalog.go
// Registration is used to make sure a node, service, and check registration is
// performed within a single transaction to avoid race conditions on state
// updates.
func (s *Restore) Registration(idx uint64, req *structs.RegisterRequest) error {
	if err := s.store.ensureRegistrationTxn(s.tx, idx, req); err != nil {
		return err
	}
	return nil
}

// EnsureRegistration is used to make sure a node, service, and check
// registration is performed within a single transaction to avoid race
// conditions on state updates.
func (s *Store) EnsureRegistration(idx uint64, req *structs.RegisterRequest) error {
	tx := s.db.WriteTxn(idx)
	defer tx.Abort()

	if err := s.ensureRegistrationTxn(tx, idx, req); err != nil {
		return err
	}

	return tx.Commit()
}

func (s *Store) ensureCheckIfNodeMatches(tx *txn, idx uint64, node string, check *structs.HealthCheck) error {
	if check.Node != node {
		return fmt.Errorf("check node %q does not match node %q",
			check.Node, node)
	}
	if err := s.ensureCheckTxn(tx, idx, check); err != nil {
```

## Developer hypothesis
Restored catalog registrations are re-applied through the same registration transaction that live registrations use, driven from the snapshot restore code. Worth checking how the index metadata of catalog entries is determined when they are re-created during a restore.
