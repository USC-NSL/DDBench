# Symptom

Streaming subscribers that connect fresh (with `Index=0`) intermittently receive an unexpected reset framing event at the start of their snapshot. This framing event is only supposed to appear when a subscriber reconnects with a stale index (`Index > 0`) to signal that their view must be reset. Receiving it on a fresh subscription causes the client to error because it expects data events, not a reset signal.

## Observable behavior

- A fresh subscriber (`Index=0`) receives events in the wrong order: first a reset framing event, then the actual snapshot data, then the end-of-snapshot marker. The correct order for a fresh subscriber is: snapshot data events, then the end-of-snapshot marker.
- The bug is triggered by a specific sequence: (1) a stale-index subscriber (`Index > 0`) connects first; (2) a fresh subscriber (`Index=0`) connects shortly after and receives the incorrect event ordering.
- The bug is timing-dependent: it only manifests when the two subscriptions happen in close succession (within a few seconds of each other).
- No error messages appear in server logs. The error manifests entirely on the client side when it receives the unexpected framing event.
- The incorrect behavior resolves on its own after a short period, making it intermittent.
