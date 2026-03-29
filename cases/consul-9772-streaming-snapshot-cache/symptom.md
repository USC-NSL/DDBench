# Symptom

Streaming subscribers that connect fresh (with `Index=0`) intermittently receive an unexpected `newSnapshotToFollow` framing event at the start of their snapshot. This framing event is only supposed to appear when a subscriber reconnects with a stale index (`Index > 0`) to signal that their view must be reset. Receiving it on a fresh subscription causes the client to error because it expects data events, not a reset signal.

## Observable behavior

- A fresh subscriber (`Index=0`) receives events in the wrong order: first a `newSnapshotToFollow` framing event, then the actual snapshot data, then `endOfSnapshot`. The correct order for a fresh subscriber is: snapshot data events, then `endOfSnapshot`.
- The bug is triggered by a specific sequence: (1) a stale-index subscriber (`Index > 0`) connects first, causing the publisher to build and cache a snapshot that includes the `newSnapshotToFollow` framing event; (2) a fresh subscriber (`Index=0`) connects next and receives the incorrectly cached snapshot.
- The bug is timing-dependent: it only manifests when the snapshot cache TTL has not expired between the two subscriptions (default is configurable, typically a few seconds).
- No error messages appear in server logs. The error manifests entirely on the client side when it receives the unexpected framing event.
- The issue persists until the cached snapshot expires (controlled by `snapCacheTTL`), after which new snapshots are built correctly.
