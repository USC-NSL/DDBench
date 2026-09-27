# Code Investigation

## What was searched
The symptom describes fetch-from-follower consumers always waiting the full `fetch.max.wait.ms` timeout. Investigated how the follower replica's high watermark update notifies waiting fetch requests in the delayed fetch purgatory.

## What was found
```
$ grep -n "processPartitionData" core/src/main/scala/kafka/server/ReplicaFetcherThread.scala
92:  override def processPartitionData(topicPartition: TopicPartition,

$ sed -n '92,140p' core/src/main/scala/kafka/server/ReplicaFetcherThread.scala
  override def processPartitionData(topicPartition: TopicPartition,
                                    fetchOffset: Long,
                                    partitionData: FetchData): Option[LogAppendInfo] = {
    ...
    // Append the leader's messages to the log
    val logAppendInfo = partition.appendRecordsToFollowerOrFutureReplica(records, isFuture = false)
    ...
    val followerHighWatermark = log.updateHighWatermark(partitionData.highWatermark)
    log.maybeIncrementLogStartOffset(leaderLogStartOffset, LeaderOffsetIncremented)
    ...
    logAppendInfo
  }
```

The method updates the follower's high watermark but does NOT call `completeDelayedFetchOrProduceRequests()` or `delayedFetchPurgatory.checkAndComplete()` afterward.

## Developer hypothesis
The follower's `processPartitionData` method in `ReplicaFetcherThread` and its post-`updateHighWatermark` control flow.
