# Solution: NATS Server #7308

## Fix
- **PR:** https://github.com/nats-io/nats-server/pull/7348
- **Commit:** `fd40cf513b17717b4070da83d3764d9af30c6a77`

## Root cause
In `applyStreamEntries` (server/jetstream_cluster.go), when processing a `deleteMsgOp`, if `removeMsg` or `eraseMsg` returns `ErrStoreEOF` (the requested sequence number is beyond the stream's last sequence), the code treats this as a fatal cluster error by returning the error from the function. The caller interprets this return as a need to reset the entire cluster state, triggering a leader election and making the stream inaccessible for several seconds.

The `ErrStoreEOF` is returned by the file store when deleting a sequence number that is greater than the stream's `LastSeq` (e.g., deleting seq 2 when only seq 1 exists). This is a normal client error, not a storage corruption signal.

## Fix description
Instead of returning `ErrStoreEOF` as a fatal error from `applyStreamEntries`, the fix:
1. Checks if the current node is the leader
2. Sends a `JSStreamMsgDeleteFailedError` response back to the client
3. Uses `continue` to proceed with the next entry instead of returning

This 12-line change in `server/jetstream_cluster.go` distinguishes between a genuine storage EOF (which should not reset cluster state) and actual fatal errors. The fix also cleans up the leader check to use the raft node directly rather than taking a lock on `js.mu`.

## How to apply
```bash
git cherry-pick fd40cf513b17717b4070da83d3764d9af30c6a77
go build -o nats-server .
```
