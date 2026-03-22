# Solution: NATS #6888

## Fix
- **Issue:** https://github.com/nats-io/nats-server/issues/6888
- **Buggy version:** v2.10.20

## Root cause

The Raft meta-stream is responsible for tracking which JetStream streams exist in the cluster. When a NATS server is terminated with `kill -9` (SIGKILL), the process has no opportunity to flush pending Raft state to disk.

Upon restart, the Raft meta-stream recovery process may fail to reconstruct the correct set of active streams because:

1. The Raft WAL for the meta-stream may have uncommitted entries that reference stream creation/deletion.
2. The snapshot of the meta-stream state may be stale (from before the stream was created).
3. Without proper consistency checks between the meta-stream state and the actual stream data on disk, the server "forgets" about streams that exist on disk but are not in the recovered meta-stream state.

The combination of ungraceful shutdown timing and Raft meta-stream recovery logic leads to streams being silently dropped from the cluster's knowledge.

## Fix description

The fix improves Raft meta-stream recovery and adds consistency checks:

1. **WAL recovery improvement:** Ensure that the Raft WAL for the meta-stream is properly replayed during recovery, even when entries were not fully committed before the crash.
2. **Consistency checks:** On startup, cross-reference the streams known to the Raft meta-stream with the stream data directories on disk. If a stream's data exists on disk but is not in the meta-stream, recover it.
3. **Snapshot integrity:** Ensure meta-stream snapshots include all active streams and are written atomically.

## How to apply
Upgrade to a NATS server version after v2.10.20 that contains the fix:
```bash
git checkout main  # or a release tag after v2.10.20
go build -o nats-server .
```

## How to verify
Create an R3 stream, perform multiple kill -9 + restart cycles on all nodes, and verify the stream is always present and accessible after restart. Run the verification script from verification.md with 10+ cycles.
