# Solution: Consul #9772 — Streaming Snapshot Cache Bug

## Root Cause

In `agent/consul/stream/event_publisher.go`, the `Subscribe()` method has a code path for handling stale-index requests (`Index > 0`) when the topic buffer has moved past the requested index. In this path, the publisher:

1. Creates a new `eventSnapshot`
2. Prepends a `newSnapshotToFollow` framing event to the snapshot buffer
3. If no cache exists, calls `snap.appendAndSplice()` to populate the snapshot with data
4. Caches the entire snapshot via `setCachedSnapshotLocked(req, snap)`

The problem is that the cached snapshot's `First` pointer points to the `newSnapshotToFollow` framing event, because it was prepended before the data. When a subsequent fresh subscriber (`Index=0`) retrieves this cached snapshot, it receives the framing event at the start, which is incorrect for a fresh subscription.

## Fix

The fix (17 lines changed in `event_publisher.go`) restructures the `Subscribe()` method to separate snapshot creation/caching from per-subscriber framing:

1. **Always create a clean snapshot first**: If no cache exists, build the snapshot (without any framing events) and cache it.
2. **For fresh subscribers (Index=0)**: Return the cached snapshot directly.
3. **For stale subscribers (Index > 0)**: Create a separate `result` snapshot, prepend the `newSnapshotToFollow` framing event, then splice in the cached snapshot. This `result` is returned to the subscriber but never cached.

This ensures the cache only ever contains clean data snapshots, and the `newSnapshotToFollow` framing event is added per-subscriber as needed.

## Fix Commit

`363d738fd2ee1ee25ad872a63894cffa8faf9df2` (merge of PR #9772)

## Diff Summary

```diff
-	if req.Index == 0 && snapFromCache != nil {
-		return e.subscriptions.add(req, snapFromCache.First), nil
+	if snapFromCache == nil {
+		snap := newEventSnapshot()
+		snap.appendAndSplice(*req, handler, topicHead)
+		e.setCachedSnapshotLocked(req, snap)
+		snapFromCache = snap
 	}
-	snap := newEventSnapshot()

-	if req.Index > 0 {
-		snap.buffer.Append([]Event{{...newSnapshotToFollow...}})
-		if snapFromCache != nil {
-			snap.buffer.AppendItem(snapFromCache.First)
-			return e.subscriptions.add(req, snap.First), nil
-		}
+	if req.Index == 0 {
+		return e.subscriptions.add(req, snapFromCache.First), nil
 	}

-	snap.appendAndSplice(*req, handler, topicHead)
-	e.setCachedSnapshotLocked(req, snap)
-	return e.subscriptions.add(req, snap.First), nil
+	result := newEventSnapshot()
+	result.buffer.Append([]Event{{...newSnapshotToFollow...}})
+	result.buffer.AppendItem(snapFromCache.First)
+	return e.subscriptions.add(req, result.First), nil
```
