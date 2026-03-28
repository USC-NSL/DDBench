# Symptom

The NATS server crashes with an unrecoverable Go runtime fatal error when multiple clients concurrently create, update, and delete consumers on a WorkQueue retention stream.

## Observable behavior
- A JetStream WorkQueue stream is configured with multiple subjects (e.g., `wq.>`). Multiple durable consumers exist, each with a distinct `FilterSubject` targeting a different partition of the stream's subject space.
- Multiple clients — each on a separate NATS connection — rapidly create, update, and delete durable consumers on the same WorkQueue stream while messages are being published and delivered.
- The server abruptly terminates with a `fatal error: concurrent map iteration and map write` message. This is a Go runtime fatal, not a panic — it cannot be recovered.
- The crash stack trace shows two goroutines involved: one in the consumer creation/deletion API request path, and the other in the stream's consumer removal path. Both are accessing the same internal map simultaneously — one iterating, the other deleting.
- The crash is non-deterministic and timing-dependent. It is more likely to trigger when:
  - Many consumers already exist on the stream (the internal iteration takes longer).
  - Each client goroutine uses its own NATS connection (requests are processed on separate server goroutines, increasing concurrency).
  - Consumer lifecycle operations (create/update/delete) happen rapidly without pauses.
- A single client connection performing all consumer operations sequentially does not trigger the crash, because requests on a single connection are serialized server-side.
- After the crash, the server process exits. All connected clients are disconnected. Persistent JetStream data on disk is intact, but any in-flight or unacknowledged messages may require redelivery after restart.
