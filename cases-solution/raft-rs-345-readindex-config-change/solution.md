# Solution: raft-rs #345

- **Issue:** https://github.com/tikv/raft-rs/issues/345
- **Fix commit:** [`513b82ce4507747a678fee7b4405c8b8b106fc12`](https://github.com/tikv/raft-rs/commit/513b82ce4507747a678fee7b4405c8b8b106fc12)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/tikv/raft-rs/pull/363
- **Commit:** `513b82ce4507747a678fee7b4405c8b8b106fc12`

## Root cause
When `remove_node` shrinks the cluster quorum (e.g., from 2 to 1), pending ReadIndex requests are not re-evaluated against the new smaller quorum. The leader's self-ack, already recorded in `ReadOnly.pending_read_index`, is now sufficient but never checked again.

## Fix description
1. **Refactors `recv_ack` and `advance`** in `src/read_only.rs` to accept `(id, &ctx)` and `(&ctx)` instead of `&Message`, enabling them to be called from `remove_node` without constructing a fake message.
2. **Extracts `handle_ready_read_index`** in `src/raft.rs` to deduplicate read response logic (local vs. remote).
3. **Adds quorum recheck in `remove_node`**: after removing a node, calls `last_pending_request_ctx()` to get the latest pending read, then checks if the existing acks now satisfy the smaller quorum. If so, advances all pending reads.

## How to apply
```bash
git checkout 513b82ce4507747a678fee7b4405c8b8b106fc12
cd harness && cargo test --no-run
```
