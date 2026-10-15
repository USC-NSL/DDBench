# Solution: raft-rs #221

- **Issue:** https://github.com/tikv/raft-rs/issues/221
- **Fix commit:** [`64571f0fb7d87e5c335f05a67b2ff5fbe90dec36`](https://github.com/tikv/raft-rs/commit/64571f0fb7d87e5c335f05a67b2ff5fbe90dec36)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix

- **PR:** https://github.com/tikv/raft-rs/pull/225
- **Commit:** `64571f0fb7d87e5c335f05a67b2ff5fbe90dec36`

## Fix locus

- **Component:** Campaign/election logic (`src/raft.rs`)
- **Files:**
  - `src/raft.rs` (+52/-34) — extracts `hup()` method that checks pending conf changes before campaigning; both `MsgHup` and `MsgTimeoutNow` handlers now go through `hup()`
  - `src/raw_node.rs` (+3/-5) — formatting cleanup
  - `src/util.rs` (+2/-1) — formatting cleanup
  - `tests/integration_cases/test_raft.rs` (+62/-0) — adds `test_conf_change_check_before_campaign`
  - `tests/integration_cases/test_raw_node.rs` (+4/-2) — formatting cleanup
  - `tests/test_util/mod.rs` (+4/-2) — formatting cleanup

## Root cause

The `MsgTimeoutNow` handler in `step_follower()` directly called `self.campaign(CAMPAIGN_TRANSFER)` without checking for pending configuration changes:

```rust
// Buggy: MsgTimeoutNow handler bypasses conf change check
MessageType::MsgTimeoutNow => {
    // ...
    self.campaign(CAMPAIGN_TRANSFER);
}
```

In contrast, the `MsgHup` handler (election timeout) DID check for pending conf changes before calling `self.campaign()`. When a conf change entry (e.g., `RemoveNode(3)`) is committed but not yet applied, the voter set is stale. A node that campaigns with a stale voter set may count votes from removed nodes or fail to count votes from new nodes.

The fix extracts the "check pending conf changes then campaign" logic into a new `hup(transfer_leader: bool)` method, then makes both `MsgHup` and `MsgTimeoutNow` go through it:

```rust
// Fixed: MsgHup and MsgTimeoutNow both go through hup()
MessageType::MsgHup => self.hup(false),
// ...
MessageType::MsgTimeoutNow => {
    // ...
    self.hup(true);
}
```

The `hup()` method also improves the range check: it uses `unstable.maybe_first_index()` (which accounts for pending snapshots) instead of only `applied + 1`, and removes the unnecessary `self.raft_log.committed > self.raft_log.applied` condition.

## Diagnosis chain

1. **Symptom**: Leader transfer fails or produces split-brain when cluster membership changes coincide with the transfer.
2. **Code path**: `step_follower()` receives `MsgTimeoutNow` → calls `self.campaign(CAMPAIGN_TRANSFER)` directly.
3. **Comparison**: `MsgHup` handler checks `num_pending_conf()` before campaigning, but `MsgTimeoutNow` does not.
4. **Root cause**: Missing pending conf change check in the `MsgTimeoutNow` handler allows campaigning with stale voter set.
5. **Fix**: Extract shared `hup()` method that both handlers call, ensuring consistent conf change checking.

## Fix description

The fix extracts a `hup(transfer_leader: bool)` method from the `MsgHup` handler, adds the conf change check, and routes both `MsgHup` and `MsgTimeoutNow` through it. The `MsgTimeoutNow` handler changes from `self.campaign(CAMPAIGN_TRANSFER)` to `self.hup(true)`.

## How to apply

```bash
git checkout 64571f0fb7d87e5c335f05a67b2ff5fbe90dec36
```

## How to verify

Run `reproduce.sh` — should print `PASS: Bug is fixed`.
