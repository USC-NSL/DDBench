# Solution: Consul #8377

- **Issue:** https://github.com/hashicorp/consul/issues/8377
- **Fix commit:** [`9bc9d3014d2d8f48c4c87926bfb98c8536364532`](https://github.com/hashicorp/consul/commit/9bc9d3014d2d8f48c4c87926bfb98c8536364532)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/hashicorp/consul/pull/8474
- **Commit:** `9bc9d3014d2d8f48c4c87926bfb98c8536364532`

## Fix locus
- **Component:** State store catalog registration (FSM snapshot restore path)
- **Files:**
  - `agent/consul/state/catalog.go` (+38/-25) — adds `preserveIndexes` parameter to `ensureNodeTxn`, `ensureServiceTxn`, `ensureCheckTxn`, and `ensureRegistrationTxn`
  - `agent/consul/fsm/snapshot_oss.go` (+1/-0) — passes `RaftIndex` through `RegisterRequest` during restore
  - `agent/structs/structs.go` (+1/-0) — embeds `RaftIndex` in `RegisterRequest`
  - `agent/consul/state/txn.go` (+3/-3) — updates transaction callers to pass `preserveIndexes=false`

## Root cause
The FSM snapshot restore path calls `ensureRegistrationTxn` → `ensureNodeTxn` / `ensureServiceTxn` / `ensureCheckTxn` for each catalog entry. These functions always overwrite `CreateIndex` and `ModifyIndex` with the current Raft index. During normal API operations, this is correct — the entry gets the index of the Raft log entry that created/modified it. But during snapshot restore, the entry already has its correct historical indexes from the snapshot data. Since the restore code doesn't preserve these, each server assigns its own snapshot restore index, producing inconsistent indexes across the cluster.

KV entries did not have this bug because they use a raw `tx.Insert` that preserves the struct fields as-is.

## Diagnosis chain
1. **Runtime observation:** Stale queries to different servers return different `CreateIndex` values for the same service. The inconsistency is permanent and affects all entries that existed before the last restart. Newly registered entries are fine.
2. **Pattern recognition:** All affected entries on a given server share the same `CreateIndex` value. This value corresponds to the Raft log index at which that server took its snapshot. This suggests the restore path is assigning the snapshot index as the `CreateIndex`.
3. **Code reasoning:** Trace the FSM snapshot restore path: `restoreRegistration` → `ensureRegistrationTxn` → `ensureNodeTxn`. In `ensureNodeTxn`, when no existing node is found, it unconditionally sets `node.CreateIndex = idx` and `node.ModifyIndex = idx`. The `idx` here is the Raft restore index, not the original CreateIndex from the snapshot data.
4. **Root cause confirmed:** The restore path does not propagate the `RaftIndex` from the snapshot data through the `RegisterRequest` to the state store functions. Unlike KV (which does a raw insert), catalog entries go through helper functions that always reassign indexes.

## Fix description
The fix adds a `preserveIndexes bool` parameter to `ensureNodeTxn`, `ensureServiceTxn`, `ensureCheckTxn`, and `ensureRegistrationTxn`. When `true` (called from snapshot restore), the functions skip overwriting `CreateIndex`/`ModifyIndex`. Additionally, the `RegisterRequest` struct embeds `RaftIndex`, and the snapshot restore code (`snapshot_oss.go`) populates this field from the snapshot data. Normal API paths pass `preserveIndexes=false`, maintaining existing behavior.

## How to apply
```bash
git checkout 9bc9d3014d2d8f48c4c87926bfb98c8536364532
make dev-build
```

## How to verify
Run `reproduce.sh` — should print `PASS: Bug is fixed`.

## Gold patch
`gold.patch` in this directory is the upstream fix commit, *including* its edits to
`agent/consul/state/catalog_test.go` and `agent/consul/fsm/snapshot_oss_test.go`. The fix
changes the signature of an internal function (`ensureCheckTxn`) that existing tests in
package `state` call. Without those test edits the package's tests, and with them the
oracle test injected into that package, do not compile. A correct agent fix has to keep
the package's tests compiling, too.
