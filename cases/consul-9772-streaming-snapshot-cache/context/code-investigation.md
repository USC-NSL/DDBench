# Code Investigation

## What was searched
The symptom describes fresh subscribers (Index=0) receiving an unexpected `newSnapshotToFollow` framing event that should only be sent to stale subscribers (Index>0). A developer would investigate how snapshots are built, cached, and served to different subscriber types.

## What was found

The `Subscribe` function in `agent/consul/stream/event_publisher.go` has a caching mechanism that conflates stale-subscriber snapshots with fresh-subscriber snapshots:

```go
// agent/consul/stream/event_publisher.go:157-199
func (e *EventPublisher) Subscribe(req *SubscribeRequest) (*Subscription, error) {
    ...
    topicHead := e.getTopicBuffer(req.Topic).Head()

    // If the client view is fresh, resume the stream.
    if req.Index > 0 && topicHead.HasEventIndex(req.Index) {
        buf := newEventBuffer()
        subscriptionHead := buf.Head()
        buf.AppendItem(topicHead.NextLink())
        return e.subscriptions.add(req, subscriptionHead), nil
    }

    snapFromCache := e.getCachedSnapshotLocked(req)
    if req.Index == 0 && snapFromCache != nil {
        return e.subscriptions.add(req, snapFromCache.First), nil  // (A) fresh subscriber uses cache
    }
    snap := newEventSnapshot()

    // if the request has an Index the client view is stale and must be reset
    // with a NewSnapshotToFollow event.
    if req.Index > 0 {
        snap.buffer.Append([]Event{{                                // (B) framing event prepended
            Topic:   req.Topic,
            Payload: newSnapshotToFollow{},
        }})

        if snapFromCache != nil {
            snap.buffer.AppendItem(snapFromCache.First)
            return e.subscriptions.add(req, snap.First), nil
        }
    }

    snap.appendAndSplice(*req, handler, topicHead)                  // (C) snapshot data appended
    e.setCachedSnapshotLocked(req, snap)                            // (D) cache includes framing event
    return e.subscriptions.add(req, snap.First), nil
}
```

The `eventSnapshot` struct tracks the buffer head:

```go
// agent/consul/stream/event_snapshot.go:11-18
type eventSnapshot struct {
    First  *bufferItem    // Head of the snapshot buffer
    buffer *eventBuffer
}
```

The race sequence:
1. A stale subscriber (Index>0, not resumable) arrives first. No cache exists.
2. At (B), `newSnapshotToFollow` is appended to `snap.buffer` — this is the FIRST event in the buffer, so `snap.First` points to it.
3. At (C), `appendAndSplice` appends the actual snapshot data and `endOfSnapshot` marker after the framing event.
4. At (D), `setCachedSnapshotLocked` caches this `snap` — whose `First` starts with the `newSnapshotToFollow` framing event.
5. A fresh subscriber (Index=0) arrives shortly after.
6. At (A), `snapFromCache.First` is returned — but this `First` points to the `newSnapshotToFollow` event from step 2.
7. The fresh subscriber receives: `newSnapshotToFollow` -> snapshot data -> `endOfSnapshot`, when it should only receive: snapshot data -> `endOfSnapshot`.

## Developer hypothesis
The shared snapshot cache in `Subscribe` and the relationship between the stale-subscriber snapshot construction path and the fresh-subscriber cache lookup path.
