# Code Investigation

## What was searched
The symptom describes the group coordinator serving committed offsets that differ from what a coordinator reloading `__consumer_offsets` serves, after transactional offset commits overlapped with deletion of the group or with the offsets partition being unloaded and reloaded. Read how `GroupMetadataManager.storeOffsets()` writes offset commits to the `__consumer_offsets` log and updates the group's in-memory state.

## What was found
```
$ cat -n core/src/main/scala/kafka/coordinator/group/GroupMetadataManager.scala | sed -n '327,492p'
   327	  private def appendForGroup(group: GroupMetadata,
   328	                             records: Map[TopicPartition, MemoryRecords],
   329	                             requestLocal: RequestLocal,
   330	                             callback: Map[TopicPartition, PartitionResponse] => Unit,
   331	                             transactionalId: String = null): Unit = {
   332	    // call replica manager to append the group message
   333	    replicaManager.appendRecords(
   334	      timeout = config.offsetCommitTimeoutMs.toLong,
   335	      requiredAcks = config.offsetCommitRequiredAcks,
   336	      internalTopicsAllowed = true,
   337	      origin = AppendOrigin.COORDINATOR,
   338	      entriesPerPartition = records,
   339	      delayedProduceLock = Some(group.lock),
   340	      responseCallback = callback,
   341	      requestLocal = requestLocal,
   342	      transactionalId = transactionalId)
   343	  }
   344	
   345	  /**
   346	   * Store offsets by appending it to the replicated log and then inserting to cache
   347	   */
   348	  def storeOffsets(group: GroupMetadata,
   349	                   consumerId: String,
   350	                   offsetMetadata: immutable.Map[TopicIdPartition, OffsetAndMetadata],
   351	                   responseCallback: immutable.Map[TopicIdPartition, Errors] => Unit,
   352	                   transactionalId: String = null,
   353	                   producerId: Long = RecordBatch.NO_PRODUCER_ID,
   354	                   producerEpoch: Short = RecordBatch.NO_PRODUCER_EPOCH,
   355	                   requestLocal: RequestLocal = RequestLocal.NoCaching): Unit = {
   356	    // first filter out partitions with offset metadata size exceeding limit
   357	    val filteredOffsetMetadata = offsetMetadata.filter { case (_, offsetAndMetadata) =>
   358	      validateOffsetMetadataLength(offsetAndMetadata.metadata)
   359	    }
   360	
   361	    group.inLock {
   362	      if (!group.hasReceivedConsistentOffsetCommits)
   363	        warn(s"group: ${group.groupId} with leader: ${group.leaderOrNull} has received offset commits from consumers as well " +
   364	          s"as transactional producers. Mixing both types of offset commits will generally result in surprises and " +
   365	          s"should be avoided.")
   366	    }
   367	
   368	    val isTxnOffsetCommit = producerId != RecordBatch.NO_PRODUCER_ID
   369	    // construct the message set to append
   370	    if (filteredOffsetMetadata.isEmpty) {
   371	      // compute the final error codes for the commit response
   372	      val commitStatus = offsetMetadata.map { case (k, _) => k -> Errors.OFFSET_METADATA_TOO_LARGE }
   373	      responseCallback(commitStatus)
   374	    } else {
   375	      getMagic(partitionFor(group.groupId)) match {
   376	        case Some(magicValue) =>
   377	          // We always use CREATE_TIME, like the producer. The conversion to LOG_APPEND_TIME (if necessary) happens automatically.
   378	          val timestampType = TimestampType.CREATE_TIME
   379	          val timestamp = time.milliseconds()
   380	
   381	          val records = filteredOffsetMetadata.map { case (topicIdPartition, offsetAndMetadata) =>
   382	            val key = GroupMetadataManager.offsetCommitKey(group.groupId, topicIdPartition.topicPartition)
   383	            val value = GroupMetadataManager.offsetCommitValue(offsetAndMetadata, interBrokerProtocolVersion)
   384	            new SimpleRecord(timestamp, key, value)
   385	          }
   386	          val offsetTopicPartition = new TopicPartition(Topic.GROUP_METADATA_TOPIC_NAME, partitionFor(group.groupId))
   387	          val buffer = ByteBuffer.allocate(AbstractRecords.estimateSizeInBytes(magicValue, compressionType, records.asJava))
   388	
   389	          if (isTxnOffsetCommit && magicValue < RecordBatch.MAGIC_VALUE_V2)
   390	            throw Errors.UNSUPPORTED_FOR_MESSAGE_FORMAT.exception("Attempting to make a transaction offset commit with an invalid magic: " + magicValue)
   391	
   392	          val builder = MemoryRecords.builder(buffer, magicValue, compressionType, timestampType, 0L, time.milliseconds(),
   393	            producerId, producerEpoch, 0, isTxnOffsetCommit, RecordBatch.NO_PARTITION_LEADER_EPOCH)
   394	
   395	          records.foreach(builder.append)
   396	          val entries = Map(offsetTopicPartition -> builder.build())
   397	
   398	          // set the callback function to insert offsets into cache after log append completed
   399	          def putCacheCallback(responseStatus: Map[TopicPartition, PartitionResponse]): Unit = {
   400	            // the append response should only contain the topics partition
   401	            if (responseStatus.size != 1 || !responseStatus.contains(offsetTopicPartition))
   402	              throw new IllegalStateException("Append status %s should only have one partition %s"
   403	                .format(responseStatus, offsetTopicPartition))
   404	
   405	            // construct the commit response status and insert
   406	            // the offset and metadata to cache if the append status has no error
   407	            val status = responseStatus(offsetTopicPartition)
   408	
   409	            val responseError = group.inLock {
   410	              if (status.error == Errors.NONE) {
   411	                if (!group.is(Dead)) {
   412	                  filteredOffsetMetadata.forKeyValue { (topicIdPartition, offsetAndMetadata) =>
   413	                    if (isTxnOffsetCommit)
   414	                      group.onTxnOffsetCommitAppend(producerId, topicIdPartition, CommitRecordMetadataAndOffset(Some(status.baseOffset), offsetAndMetadata))
   415	                    else
   416	                      group.onOffsetCommitAppend(topicIdPartition, CommitRecordMetadataAndOffset(Some(status.baseOffset), offsetAndMetadata))
   417	                  }
   418	                }
   419	
   420	                // Record the number of offsets committed to the log
   421	                offsetCommitsSensor.record(records.size)
   422	
   423	                Errors.NONE
   424	              } else {
   425	                if (!group.is(Dead)) {
   426	                  if (!group.hasPendingOffsetCommitsFromProducer(producerId))
   427	                    removeProducerGroup(producerId, group.groupId)
   428	                  filteredOffsetMetadata.forKeyValue { (topicIdPartition, offsetAndMetadata) =>
   429	                    if (isTxnOffsetCommit)
   430	                      group.failPendingTxnOffsetCommit(producerId, topicIdPartition)
   431	                    else
   432	                      group.failPendingOffsetWrite(topicIdPartition, offsetAndMetadata)
   433	                  }
   434	                }
   435	
   436	                debug(s"Offset commit $filteredOffsetMetadata from group ${group.groupId}, consumer $consumerId " +
   437	                  s"with generation ${group.generationId} failed when appending to log due to ${status.error.exceptionName}")
   438	
   439	                // transform the log append error code to the corresponding the commit status error code
   440	                status.error match {
   441	                  case Errors.UNKNOWN_TOPIC_OR_PARTITION
   442	                       | Errors.NOT_ENOUGH_REPLICAS
   443	                       | Errors.NOT_ENOUGH_REPLICAS_AFTER_APPEND =>
   444	                    Errors.COORDINATOR_NOT_AVAILABLE
   445	
   446	                  case Errors.NOT_LEADER_OR_FOLLOWER
   447	                       | Errors.KAFKA_STORAGE_ERROR =>
   448	                    Errors.NOT_COORDINATOR
   449	
   450	                  case Errors.MESSAGE_TOO_LARGE
   451	                       | Errors.RECORD_LIST_TOO_LARGE
   452	                       | Errors.INVALID_FETCH_SIZE =>
   453	                    Errors.INVALID_COMMIT_OFFSET_SIZE
   454	
   455	                  case other => other
   456	                }
   457	              }
   458	            }
   459	
   460	            // compute the final error codes for the commit response
   461	            val commitStatus = offsetMetadata.map { case (topicIdPartition, offsetAndMetadata) =>
   462	              if (validateOffsetMetadataLength(offsetAndMetadata.metadata))
   463	                (topicIdPartition, responseError)
   464	              else
   465	                (topicIdPartition, Errors.OFFSET_METADATA_TOO_LARGE)
   466	            }
   467	
   468	            // finally trigger the callback logic passed from the API layer
   469	            responseCallback(commitStatus)
   470	          }
   471	
   472	          if (isTxnOffsetCommit) {
   473	            group.inLock {
   474	              addProducerGroup(producerId, group.groupId)
   475	              group.prepareTxnOffsetCommit(producerId, offsetMetadata)
   476	            }
   477	          } else {
   478	            group.inLock {
   479	              group.prepareOffsetCommit(offsetMetadata)
   480	            }
   481	          }
   482	
   483	          appendForGroup(group, entries, requestLocal, putCacheCallback, transactionalId)
   484	
   485	        case None =>
   486	          val commitStatus = offsetMetadata.map { case (topicIdPartition, _) =>
   487	            (topicIdPartition, Errors.NOT_COORDINATOR)
   488	          }
   489	          responseCallback(commitStatus)
   490	      }
   491	    }
   492	  }
```

## Developer hypothesis
`storeOffsets()` changes the group's in-memory offset state and appends to the log as separate steps, and the result of the append is applied to the group in a callback. Worth checking what keeps the cached group state and the log in agreement when other operations on the same group (deletion, unloading of its offsets partition) run while a transactional offset commit is still in progress.
