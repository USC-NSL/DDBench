# Reproduce: Consul #9772

## Prerequisites
- Run inside `./bench.sh shell consul-9772-streaming-snapshot-cache`: the Consul repository at the buggy commit is at `/workspace/src`, and the Go toolchain is in the image.

## Step 1: Set up a snapshot handler and event publisher

Create an `EventPublisher` with a snapshot handler that returns two events and a snapshot cache TTL of 1 second.

```go
handlers := SnapshotHandlers{
    testTopic: func(req SubscribeRequest, buf SnapshotAppender) (uint64, error) {
        buf.Append([]Event{testSnapshotEvent})
        buf.Append([]Event{nextEvent})
        return 3, nil
    },
}
publisher := NewEventPublisher(handlers, time.Second)
go publisher.Run(ctx)
```

## Step 2: Publish events to the topic buffer

Publish the same events to the topic buffer so they exist in the stream history.

```go
publisher.publishEvent([]Event{testSnapshotEvent})
publisher.publishEvent([]Event{nextEvent})
```

## Step 3: Subscribe with a stale index (Index=1)

Subscribe with `Index=1`. Since the topic buffer has moved past index 1, the publisher builds a new snapshot prepended with `newSnapshotToFollow`. This snapshot (including the framing event) gets cached.

```go
req := &SubscribeRequest{Topic: testTopic, Key: "sub-key", Index: 1}
sub, err := publisher.Subscribe(req)
// Consume: newSnapshotToFollow, testSnapshotEvent, nextEvent, endOfSnapshot
sub.Unsubscribe()
```

## Step 4: Subscribe fresh (Index=0) and observe the bug

Replace the snapshot handler with one that errors (to prove the cache is used). Subscribe with `Index=0`.

```go
newReq := &SubscribeRequest{Topic: testTopic, Key: "sub-key", Index: 0}
sub, err = publisher.Subscribe(newReq)
// BUG: First event is newSnapshotToFollow (unexpected for Index=0)
// EXPECTED: First event should be testSnapshotEvent
```

## Expected result (bug present)
The fresh subscriber receives `newSnapshotToFollow` as the first event, which is wrong. A fresh subscriber should receive data events directly, not a reset framing event.

## Oracle verdict

`./bench.sh reproduce consul-9772-streaming-snapshot-cache` rebuilds the worktree and runs the oracle (`reproduce.sh`), which injects Steps 1-4 as a Go test into `agent/consul/stream`:

- **FAIL** (exit 1): the test fails or times out (60 s): the fresh subscriber (`Index=0`; the snapshot handler now returns an error, so the snapshot must come from the cache) does not receive `testSnapshotEvent`, `nextEvent`, `endOfSnapshot` in that order (e.g. its first event is `newSnapshotToFollow`), or the stale-index subscriber does not receive `newSnapshotToFollow`, both events and `endOfSnapshot` at index 3. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): the stale-index subscriber receives `newSnapshotToFollow`, the two snapshot events and `endOfSnapshot`, and the fresh subscriber receives the two snapshot events first, then `endOfSnapshot`.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or the `agent/consul/stream` package is missing), or Go module downloads fail so the oracle test cannot run.
