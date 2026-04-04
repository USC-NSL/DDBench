# Code Investigation

## What was searched
The symptom describes stale transactional offset state surviving after a storage failure. Investigated the ordering of in-memory state mutation vs. log persistence in the `storeOffsets` method.

## What was found
```
$ sed -n '478,483p' core/src/main/scala/kafka/coordinator/group/GroupMetadataManager.scala
          if (isTxnOffsetCommit) {
            group.inLock {
              addProducerGroup(producerId, group.groupId)
              group.prepareTxnOffsetCommit(producerId, offsetMetadata)
            }
          } else {
            group.inLock {
              group.prepareOffsetCommit(offsetMetadata)
            }
          }

          appendForGroup(group, entries, requestLocal, putCacheCallback, transactionalId)
```

The method first calls `group.prepareTxnOffsetCommit()` which mutates in-memory state, THEN calls `appendForGroup()` to persist to the log. The `prepareTxnOffsetCommit` method:

```
$ sed -n '668,678p' core/src/main/scala/kafka/coordinator/group/GroupMetadata.scala
  def prepareTxnOffsetCommit(producerId: Long, offsets: Map[TopicIdPartition, OffsetAndMetadata]): Unit = {
    trace(s"TxnOffsetCommit for producer $producerId and group $groupId with offsets $offsets is pending")
    receivedTransactionalOffsetCommits = true
    val producerOffsets = pendingTransactionalOffsetCommits.getOrElseUpdate(producerId,
      mutable.Map.empty[TopicPartition, CommitRecordMetadataAndOffset])

    offsets.forKeyValue { (topicIdPartition, offsetAndMetadata) =>
      producerOffsets.put(topicIdPartition.topicPartition, CommitRecordMetadataAndOffset(None, offsetAndMetadata))
    }
  }
```

This inserts entries into `pendingTransactionalOffsetCommits` immediately. If the subsequent `appendForGroup` fails (e.g., I/O error), the `putCacheCallback` error path calls `failPendingTxnOffsetCommit` to clean up:

```
$ sed -n '686,697p' core/src/main/scala/kafka/coordinator/group/GroupMetadata.scala
  def failPendingTxnOffsetCommit(producerId: Long, topicIdPartition: TopicIdPartition): Unit = {
    val topicPartition = topicIdPartition.topicPartition
    pendingTransactionalOffsetCommits.get(producerId) match {
      case Some(pendingOffsets) =>
        val pendingOffsetCommit = pendingOffsets.remove(topicPartition)
        ...
        if (pendingOffsets.isEmpty)
          pendingTransactionalOffsetCommits.remove(producerId)
      case _ =>
    }
  }
```

However, if the callback itself doesn't execute (e.g., the coordinator crashes or the response is lost), the in-memory `pendingTransactionalOffsetCommits` retains stale entries that were never persisted.

## Developer hypothesis
The `prepareTxnOffsetCommit` call site relative to `appendForGroup` in `storeOffsets`, and the `failPendingTxnOffsetCommit` cleanup callback registration inside `appendForGroup`.
