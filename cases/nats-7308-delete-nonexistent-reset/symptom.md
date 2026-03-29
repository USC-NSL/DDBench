# Symptom

Deleting a non-existent message from a clustered JetStream stream causes the stream to become inaccessible for several seconds.

When a client calls `JetStreamContext.DeleteMsg("stream-name", nonExistentSeq)` with a sequence number that is beyond the stream's last sequence, the call hangs for several seconds and then returns a "context deadline exceeded" error. During this period, the stream shows as "Inaccessible" and all operations on it fail.

For example, with a stream containing a single message (seq 1):
- Deleting seq 1 succeeds normally.
- Deleting seq 2 (does not exist, beyond EOF) causes the entire cluster state to reset, triggering a leader election and making the stream unavailable.

The issue only affects streams with replication factor > 1 (R3, etc.) in clustered mode. R1 streams handle the error correctly through a different code path.

Error observed by the client:
```
nats: context deadline exceeded
```

The NATS dashboard shows the stream as inaccessible:
```
Inaccessible Streams: test-stream
```
