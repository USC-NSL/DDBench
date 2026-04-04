# Code Investigation

## What was searched
Checked whether the leader-side write path correctly notifies the delayed fetch purgatory after a high watermark change, to contrast with the follower path.

## What was found
```
$ sed -n '610,630p' core/src/main/scala/kafka/server/ReplicaManager.scala
      actionQueue.add {
        () =>
          localProduceResults.foreach {
            case (topicPartition, result) =>
              val requestKey = TopicPartitionOperationKey(topicPartition)
              result.info.leaderHwChange match {
                case LeaderHwChange.Increased =>
                  // some delayed operations may be unblocked after HW changed
                  delayedProducePurgatory.checkAndComplete(requestKey)
                  delayedFetchPurgatory.checkAndComplete(requestKey)
                  delayedDeleteRecordsPurgatory.checkAndComplete(requestKey)
                case LeaderHwChange.Same =>
                  // probably unblock some follower fetch requests since log end offset has been updated
                  delayedFetchPurgatory.checkAndComplete(requestKey)
                case LeaderHwChange.None =>
                  // nothing
              }
          }
      }
```

The leader path in `ReplicaManager.appendToLocalLog` explicitly checks for HW changes and calls `delayedFetchPurgatory.checkAndComplete()` to wake up waiting consumers.

```
$ grep -n "completeDelayedFetchOrProduceRequests" core/src/main/scala/kafka/server/ReplicaManager.scala
328:  protected def completeDelayedFetchOrProduceRequests(topicPartition: TopicPartition): Unit = {
463:      completeDelayedFetchOrProduceRequests(topicPartition)
1705:        completeDelayedFetchOrProduceRequests(partition.topicPartition)
2223:      partitionsToStartFetching.keySet.foreach(completeDelayedFetchOrProduceRequests)
```

Multiple other code paths (stopReplica, makeFollower, becomeLeaderOrFollower) call the purgatory notification helper after state changes. The follower's `processPartitionData` in `ReplicaFetcherThread` is the only path that updates HW without notifying the purgatory.

## Developer hypothesis
The follower's `processPartitionData` in `ReplicaFetcherThread` compared to the leader's `appendToLocalLog` and other state-change paths (`stopReplica`, `makeFollower`, `becomeLeaderOrFollower`) in `ReplicaManager`.
