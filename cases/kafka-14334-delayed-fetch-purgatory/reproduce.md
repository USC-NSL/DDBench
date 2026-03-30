# Reproduce: Kafka #14334

## Step 1: Inject and run the regression test

The bug is in `ReplicaFetcherThread.processPartitionData()`, which appends replicated data and updates the follower's high watermark but never notifies the `DelayedFetchPurgatory` that new data is available. This can be reproduced with a unit test in `ReplicaFetcherThreadTest` that mocks the `ReplicaManager` and verifies that `completeDelayedFetchRequests` is called after the follower's high watermark is updated.

```bash
cd kafka
./gradlew :core:test --tests "kafka.server.ReplicaFetcherThreadTest.testLocalFetchCompletionIfHighWatermarkUpdated*" -x spotlessCheck
```

The injected test does the following:
1. Creates a `ReplicaFetcherThread` with a mocked `ReplicaManager` and `UnifiedLog`.
2. Configures the mock log to return `Some(highWatermark)` from `maybeUpdateHighWatermark()` (simulating that the HW changes).
3. Calls `processPartitionData()` for two topic partitions to append records and update the HW.
4. Verifies that `completeDelayedFetchRequests` has NOT been called yet (the buffer accumulates partitions).
5. Calls `doWork()` which should drain the buffer and invoke `completeDelayedFetchRequests` with both partitions.
6. Verifies that the `partitionsWithNewHighWatermark` buffer is cleared after the call.

A second parameterized variant (with `highWatermarkUpdated=false`) verifies that `completeDelayedFetchRequests` is NOT called when the HW does not change.

## Expected result (bug present)

The test fails because on the buggy code, `ReplicaFetcherThread` does not override `doWork()` and does not track partitions with new high watermarks. There is no mechanism to call `completeDelayedFetchRequests` after replication, so the mock verification fails:

```
Wanted 1 time but was 0 times
replicaManager.completeDelayedFetchRequests(any[Seq[TopicPartition]])
```

## Expected result (fix applied)

The test passes. `ReplicaFetcherThread.doWork()` calls `completeDelayedFetchRequests()` after each fetch cycle, draining the buffer of partitions whose high watermark changed and completing any pending delayed fetch requests.
