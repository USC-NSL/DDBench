# Reproduce: Consul #9772

## Prerequisites
- Go 1.13+ installed
- Consul repository checked out at the buggy commit

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
