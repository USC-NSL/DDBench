# Solution: NATS Server #6374

- **Issue:** https://github.com/nats-io/nats-server/issues/6374
- **Fix commit:** [`4be933fc655c3d35b678a74402dacd8c0448c0a7`](https://github.com/nats-io/nats-server/commit/4be933fc655c3d35b678a74402dacd8c0448c0a7)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/nats-io/nats-server/pull/6387
- **Commit:** `4be933fc655c3d35b678a74402dacd8c0448c0a7`

## Root cause

Two bugs in `server/consumer.go`:

1. **`o.awl` not reset on leader step-down:** When a consumer leader steps down, `o.setLeader(false)` calls `o.ackMsgs.drain()` to clear pending ack messages. However, `o.awl` (the atomic counter tracking inflight acks) is not reset to zero. When the consumer becomes leader again, `checkPending` sees the non-zero `o.awl` and short-circuits, assuming there are still acks being processed. This prevents any message redelivery, making the consumer appear stuck.

2. **Deleted messages not cleaned from redelivery state:** In `getNextMsg()`, when a message scheduled for redelivery has been deleted from the stream (returning `ErrStoreMsgNotFound` or `errDeletedMsg`), the code returns the error immediately without removing the stale sequence from `o.pending` and `o.rdc`. The consumer keeps trying to redeliver the deleted message on subsequent calls, causing severe slowdown.

## Fix description

Two changes in `server/consumer.go` (16 lines changed):

1. **Line ~1548:** After `o.ackMsgs.drain()` in `setLeader(false)`, add `atomic.StoreInt64(&o.awl, 0)` to reset the ack wait counter.

2. **Lines ~4021-4041:** Restructure the redelivery load logic so that when `LoadMsg` returns `ErrStoreMsgNotFound` or `errDeletedMsg`, the code deletes the sequence from `o.pending` and `o.rdc` and continues the loop instead of returning the error. The `if seq > 0` guard is removed so the cleanup logic always runs.

## How to apply
```bash
git checkout 4be933fc655c3d35b678a74402dacd8c0448c0a7
go build -o nats-server .
```
