# Solution: NATS Server #6455

- **Issue:** https://github.com/nats-io/nats-server/issues/6455
- **Fix commit:** [`bc18f1a4cbdbeebbfb09913a0a760c9f6bf8ac3a`](https://github.com/nats-io/nats-server/commit/bc18f1a4cbdbeebbfb09913a0a760c9f6bf8ac3a) — Merge commit of the fix PR; the change itself is 58cafceab177002297438dc1f4d3db3b6a7a22f4.
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Root Cause

When a clustered JetStream stream encounters a "last sequence mismatch" error, `resetClusteredState()` in `server/jetstream_cluster.go` tears down the stream via `mset.stop(shouldDelete, false)` and then recreates it via `js.processClusterCreateStream(acc, sa)`.

For `errLastSeqMismatch`, `shouldDelete` is `false`, so `stop()` does NOT call `js.releaseStreamResources()`. However, the subsequent stream recreation in `addStreamWithAssignment()` (`server/stream.go`) unconditionally calls `mset.js.reserveStreamResources(&mset.cfg)`, adding the stream's `MaxBytes` to the reserved tally a second time.

Each reset cycle adds another `MaxBytes` to `js.storeReserved`, causing the reserved bytes to grow without bound. Eventually the server reports disk full and refuses to create new streams.

Note: For `errFirstSequenceMismatch`, `shouldDelete` is `true`, so `stop()` DOES release resources before recreation. That code path is not affected by this bug.

## Fix

**PR:** https://github.com/nats-io/nats-server/pull/6457
**Commit:** bc18f1a4cbdbeebbfb09913a0a760c9f6bf8ac3a (merge), 58cafceab177002297438dc1f4d3db3b6a7a22f4 (fix)

The fix adds a `resetting` boolean field to `streamAssignment` and uses it to skip redundant `reserveStreamResources()` calls during stream recreation:

### server/jetstream_cluster.go

Add `resetting` field to `streamAssignment` struct:
```go
type streamAssignment struct {
    // ... existing fields ...
    resetting   bool // i.e. there was an error, and we're stopping and starting the stream
    err         error
}
```

Set the flag before recreating the stream in `resetClusteredState()`:
```go
// Mark stream assignment as resetting, so we don't double-account reserved resources.
// But only if we're not also releasing the resources as part of the delete.
sa.resetting = !shouldDelete
```

### server/stream.go

In `addStreamWithAssignment()`, check the `resetting` flag before reserving resources:
```go
reserveResources := true
if sa != nil {
    mset.setStreamAssignment(sa)

    // If the stream is resetting we must not double-account resources, they were already accounted for.
    js.mu.Lock()
    if sa.resetting {
        reserveResources, sa.resetting = false, false
    }
    js.mu.Unlock()
}

// ...

// Reserve resources if MaxBytes present.
if reserveResources {
    mset.js.reserveStreamResources(&mset.cfg)
}
```

Total change: 15 lines added, 1 line modified across 2 files.
