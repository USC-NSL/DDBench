# Solution: Kvrocks #3356

## Fix
- **PR:** https://github.com/apache/kvrocks/pull/3357
- **Commit:** `559a667bef223a07fea350a27168e91fe0a74601`

## Root cause

The replication feed thread in Kvrocks reads WAL entries and sends them to connected replicas. When a replica is slow to consume data (e.g., due to network issues), the feed thread blocks indefinitely on the socket write operation, waiting for the replica to acknowledge the data.

While the feed thread is blocked:
- New WAL entries keep being written by client operations.
- The feed thread cannot advance the consumer offset.
- Old WAL files cannot be garbage collected because the slow consumer's offset still references them.
- WAL grows unboundedly until disk is exhausted.

There is no timeout or backpressure mechanism to handle slow consumers.

## Fix description

The fix adds a timeout and backpressure mechanism to the replication feed thread:

- When writing to a replica socket, apply a timeout. If the write does not complete within the timeout, disconnect the slow replica rather than blocking indefinitely.
- This allows the feed thread to continue processing and WAL files to be garbage collected.
- The disconnected replica will reconnect and perform a partial or full resync as needed.

## How to apply
```bash
git checkout 559a667bef223a07fea350a27168e91fe0a74601
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

## How to verify
Run sustained write load with a throttled replica. Verify that WAL size remains bounded and the master does not exhaust disk space. The slow replica should be disconnected and reconnect automatically.
