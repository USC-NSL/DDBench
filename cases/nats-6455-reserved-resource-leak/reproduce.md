# Reproduce: NATS Server #6455

## Overview

The bug is in the interaction between `resetClusteredState()` and `reserveStreamResources()` during stream recreation. When a clustered stream encounters an error like "last sequence mismatch", it resets by stopping and recreating the stream. The recreation path unconditionally calls `reserveStreamResources()`, double-counting the `MaxBytes` allocation.

## Step 1: Create a 3-node JetStream cluster

```go
c := createJetStreamClusterExplicit(t, "R3S", 3)
```

## Step 2: Create an R3 stream with MaxBytes

```go
maxBytes := int64(1024 * 1024 * 1024) // 1 GiB
js.AddStream(&nats.StreamConfig{
    Name:     "TEST",
    Subjects: []string{"foo"},
    Replicas: 3,
    MaxBytes: maxBytes,
})
```

## Step 3: Verify initial reserved resources

```go
sl := c.streamLeader(globalAccountName, "TEST")
mem, store, err := sl.JetStreamReservedResources()
// store should equal maxBytes (1 GiB)
```

## Step 4: Trigger resetClusteredState

```go
acc, _ := sl.lookupAccount(globalAccountName)
mset, _ := acc.lookupStream("TEST")
mset.resetClusteredState(errLastSeqMismatch)
```

## Step 5: Wait for reset to complete

```go
// Wait until the stream assignment's raft group node is replaced
// (indicating the stream has been torn down and recreated)
checkFor(t, 5*time.Second, 500*time.Millisecond, func() error {
    if sa.Group.node == nil || sa.Group.node == saGroupNode {
        return errors.New("waiting for reset to complete")
    }
    return nil
})
```

## Step 6: Check reserved resources (bug manifests here)

```go
mem, store, err = sl.JetStreamReservedResources()
// BUG: store == 2 * maxBytes (double-counted)
// EXPECTED: store == maxBytes (counted once)
```

## Root cause

In `server/stream.go`, the stream creation function `addStreamWithAssignment()` unconditionally calls `mset.js.reserveStreamResources(&mset.cfg)`. When `resetClusteredState()` stops a stream (without releasing resources for non-delete resets) and then calls `processClusterCreateStream()` to recreate it, the resources get reserved a second time.
