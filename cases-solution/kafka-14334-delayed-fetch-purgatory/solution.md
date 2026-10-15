# Solution: Kafka #14334

- **Issue:** https://issues.apache.org/jira/browse/KAFKA-14334
- **Fix commit:** [`dbf5826cd545820652ed6d136727aa80a03f4f54`](https://github.com/apache/kafka/commit/dbf5826cd545820652ed6d136727aa80a03f4f54)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/apache/kafka/pull/12783
- **Commit:** `dbf5826cd545820652ed6d136727aa80a03f4f54`

## Fix locus
- **Component:** Replica fetcher / delayed fetch purgatory
- **Files:** `core/src/main/scala/kafka/server/ReplicaFetcherThread.scala` (+25, -2)

## Root cause

When a follower replica processes fetched data from the leader in `ReplicaFetcherThread.processPartitionData()`, it appends the records to the local log and updates the follower's high watermark via `log.updateHighWatermark()`. However, it never notifies the `DelayedFetchPurgatory` that new data is available.

Kafka uses a "purgatory" pattern for delayed operations: when a fetch request arrives at a follower but there is no new data, the request is stored in the `DelayedFetchPurgatory` and waits until either (a) new data becomes available, or (b) `fetch.max.wait.ms` expires. The purgatory is checked/completed when:
- A producer writes to the leader (via `KafkaApis.handleFetchRequest` calling `replicaManager.tryCompleteActions()`)
- **But NOT when a follower receives replicated data** -- this is the bug.

As a result, consumers configured with `fetch.from.follower.enabled=true` always wait the full `fetch.max.wait.ms` timeout before receiving data, even though the data has already been replicated to the follower. This negates the latency benefit of fetching from a nearby follower.

## Fix description

The fix adds three key changes to `ReplicaFetcherThread`:

1. **Track partitions with new high watermark** -- A new mutable buffer `partitionsWithNewHighwatermark` accumulates topic partitions whose HW changed during `processPartitionData()`:
```scala
private[server] val partitionsWithNewHighWatermark = mutable.Buffer[TopicPartition]()
```

2. **Override `doWork()` to complete delayed fetches** -- After each fetch cycle, the overridden `doWork()` drains the buffer and calls `completeDelayedFetchRequests`:
```scala
override def doWork(): Unit = {
  super.doWork()
  completeDelayedFetchRequests()
}

private def completeDelayedFetchRequests(): Unit = {
  if (partitionsWithNewHighWatermark.nonEmpty) {
    replicaMgr.completeDelayedFetchRequests(partitionsWithNewHighWatermark.toSeq)
    partitionsWithNewHighWatermark.clear()
  }
}
```

3. **Use `maybeUpdateHighWatermark` instead of `updateHighWatermark`** -- A new method `UnifiedLog.maybeUpdateHighWatermark()` returns `Option[Long]` (the new HW if it changed, `None` otherwise), allowing `processPartitionData()` to only add partitions to the buffer when the HW actually changes:
```scala
log.maybeUpdateHighWatermark(partitionData.highWatermark).foreach { newHighWatermark =>
  partitionsWithNewHighWatermark += topicPartition
}
```

Additionally, a new method `ReplicaManager.completeDelayedFetchRequests()` is added to complete delayed fetch requests for specific topic partitions:
```scala
private[server] def completeDelayedFetchRequests(topicPartitions: Seq[TopicPartition]): Unit = {
  topicPartitions.foreach(tp => delayedFetchPurgatory.checkAndComplete(TopicPartitionOperationKey(tp)))
}
```

## Diagnosis chain
1. **Runtime evidence:** Consumers fetching from followers observe that data is never delivered promptly -- they always wait the full `fetch.max.wait.ms`. This suggests the purgatory is never being woken up on the follower.
2. **Narrowing the component:** The delayed fetch purgatory on the follower should be completed when new data arrives via replication. The code path for follower replication is `ReplicaFetcherThread.processPartitionData()`.
3. **Code-level reasoning:** `processPartitionData()` calls `log.updateHighWatermark()` but never calls `delayedFetchPurgatory.checkAndComplete()`. The purgatory is only completed in `KafkaApis` when handling direct fetch requests, not when the follower receives replicated data. This means any pending delayed fetches on the follower remain stuck until the timeout.

## Key files
- `core/src/main/scala/kafka/server/ReplicaFetcherThread.scala` (+25, -2) -- override `doWork()`, track HW updates, complete delayed fetches
- `core/src/main/scala/kafka/log/UnifiedLog.scala` (+22, -2) -- new `maybeUpdateHighWatermark()` method
- `core/src/main/scala/kafka/server/ReplicaManager.scala` (+9, -0) -- new `completeDelayedFetchRequests()` method
- `core/src/main/scala/kafka/server/KafkaApis.scala` (+1, -0) -- comment clarifying delayed fetch completion
- `core/src/test/scala/unit/kafka/server/ReplicaFetcherThreadTest.scala` (+78, -5) -- unit tests for the fix

## How to apply
```bash
git checkout dbf5826cd545820652ed6d136727aa80a03f4f54
./gradlew jar -x test -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet
```

## Gold patch
`gold.patch` in this directory is the source part of the upstream fix commit (`core/src/main`
only). It excludes the test changes and also the two `jmh-benchmarks` edits: those adapt the
benchmarks to a changed `TestUtils.createBrokerConfig` signature in the test tree, and
applying them without the test changes breaks the build.
