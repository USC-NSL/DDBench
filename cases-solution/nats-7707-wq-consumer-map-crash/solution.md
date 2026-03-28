# Solution: NATS #7707

## Fix
- **PR:** https://github.com/nats-io/nats-server/pull/7708
- **Commit:** `3a90a2d087b792c10d4cbed27f3cc5ef0fb77571`

## Fix locus
- **Component:** JetStream stream / consumer partition management
- **Files:** `server/consumer.go`, `server/stream.go`

## Diagnosis chain
1. **Runtime evidence:** The NATS server crashes with `fatal error: concurrent map iteration and map write`. The stack trace points to goroutines in the consumer creation path and the message delivery path accessing the same map concurrently.
2. **Narrowing the component:** The fatal error occurs in the WorkQueue stream consumer partition logic. The crash is reproducible under concurrent consumer create/delete operations on a WQ stream, pointing to `partitionUnique` as the contention point.
3. **Code-level reasoning:** In `consumer.go`, the stream lock is released before calling `partitionUnique()`. This function iterates `mset.consumers` without holding the lock, while concurrent consumer operations modify the map. The fix keeps the lock held during `partitionUnique` and adds read-lock protection for consumer subject filter access.

## Root cause

In `server/consumer.go`, the `addConsumerWithAssignment` function releases the stream lock (`mset.mu.Unlock()`) before calling `mset.partitionUnique()`. The `partitionUnique` function in `server/stream.go` iterates over `mset.consumers` (a map) and also accesses each consumer's `o.subjf` field. Without the stream lock held, concurrent consumer create/delete operations modify the `mset.consumers` map while `partitionUnique` is iterating it. Similarly, `o.subjf` is read without the consumer's read lock, so a concurrent consumer update can modify it during iteration.

Go's runtime detects this as a fatal `concurrent map iteration and map write` and terminates the process.

## Fix description

The fix ensures proper lock ordering:

1. **`server/consumer.go`:** The `mset.mu.Unlock()` call is moved after the `partitionUnique` check and the `ActionCreate` duplicate check, so the stream lock is held during the entire partition uniqueness validation. The unlock is placed just before `eo.updateConfig()` which needs the lock released.

2. **`server/stream.go`:** Inside `partitionUnique`, the consumer's read lock (`o.mu.RLock()`) is acquired before accessing `o.subjf`, and released after the iteration. This prevents concurrent writes to the consumer's subject filters from racing with the read.

## How to apply
```bash
git checkout 3a90a2d087b792c10d4cbed27f3cc5ef0fb77571
go build -o nats-server .
```

## How to verify
Run `reproduce.sh` which injects a test that concurrently creates, updates, and deletes consumers on a WorkQueue stream. With the fix applied, no race condition or crash should be detected across 5 iterations with the Go race detector enabled.
