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

## Oracle verdict

`./bench.sh reproduce nats-6455-reserved-resource-leak` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): in a 3-node cluster with an R3 stream limited to `MaxBytes` = 1 GiB, after the stream's clustered state is reset (once for a last-sequence and once for a first-sequence mismatch), the stream leader reports reserved storage other than 1 GiB (e.g. 2 GiB) or non-zero reserved memory, or the reset does not complete within 5 s. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): in both subtests the reset completes and the leader's reserved storage stays exactly 1 GiB with zero reserved memory.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh`, the `nats-server` binary or the case's `inject_test.go` is missing), or Go module downloads fail so the oracle test cannot run.
