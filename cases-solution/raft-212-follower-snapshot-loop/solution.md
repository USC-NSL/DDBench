# Solution: hashicorp/raft #212

## Fix
- **PR:** https://github.com/hashicorp/raft/pull/213
- **Commit:** `37d2320db05ca622195063977ff5d4fbe0cd8ed8`

## Root cause

When the leader sends a snapshot to an out-of-date follower via `InstallSnapshot`, the follower may reject the snapshot (e.g., because it has a higher term or the snapshot is malformed). However, the `installSnapshot` handler on the follower does not consume the snapshot data from the stream when it rejects the snapshot.

The unconsumed snapshot data remains in the transport's stream. When the leader sends the next RPC (which could be an AppendEntries or another InstallSnapshot), the transport tries to decode the next message but instead reads the leftover snapshot bytes, interpreting them as an RPC command. This causes a decode error, and the leader retries with another snapshot, repeating the cycle.

The sequence:
1. Leader sends InstallSnapshot RPC with snapshot data stream.
2. Follower rejects the snapshot but does NOT read/drain the snapshot data from the stream.
3. Leftover snapshot bytes remain in the transport stream.
4. Next RPC from leader hits leftover bytes, fails to decode.
5. Leader retries with another InstallSnapshot, goto step 2.

## Fix description

Ensure that `InstallSnapshot` always consumes (drains) the snapshot data from the stream, even when the snapshot is rejected. This is done by reading and discarding the remaining bytes from the snapshot reader before returning an error:

```go
func (r *Raft) installSnapshot(rpc RPC, req *InstallSnapshotRequest, snap io.ReadCloser) {
    defer snap.Close()  // Always close (and drain) the snapshot stream

    // ... validation logic ...
    if shouldReject {
        // Drain the snapshot data before returning error
        io.Copy(io.Discard, snap)
        rpc.Respond(nil, fmt.Errorf("rejected snapshot"))
        return
    }
    // ... normal install logic ...
}
```

## How to apply
```bash
git checkout 37d2320db05ca622195063977ff5d4fbe0cd8ed8
go mod download
go test -v -run TestSnapshotInstallLoop -timeout 120s
```

## How to verify
Run the snapshot install test. The follower should successfully catch up after reconnecting, with no infinite retry loop.
