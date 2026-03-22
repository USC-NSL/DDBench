# Solution: hashicorp/raft #358

## Fix
- **PR:** https://github.com/hashicorp/raft/pull/362
- **Commit:** `7b09f38f739f486a692096c35236c7eef094e933`

## Root cause
In `snapshot.go`, lines 231-235, after a snapshot is taken, the code computes a compaction range and calls `DeleteRange(minLog, max)` without checking that `max >= minLog`. When the snapshot's last included index is behind the current log's first index (which can happen after receiving a snapshot from a leader), `max` can be less than `minLog`, resulting in an invalid negative range.

## Fix description
Add a bounds check before calling `DeleteRange`: if `max <= minLog`, skip the truncation entirely. This prevents the invalid range from being passed to the log store.

## Key files
- `snapshot.go` — around lines 231-235, the compaction logic after snapshot

## How to apply
```bash
git checkout 7b09f38f739f486a692096c35236c7eef094e933
go test ./...
```
