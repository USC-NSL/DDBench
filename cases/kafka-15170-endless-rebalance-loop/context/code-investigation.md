# Code Investigation

## What was searched
The symptom describes the cooperative sticky assignor rebalancing endlessly when rack-aware assignment is enabled and some previously owned partitions sit on racks that do not match their consumer. Searched for where rack mismatches are taken into account in `AbstractStickyAssignor` and read the phase that re-assigns previously owned partitions.

## What was found
```
$ grep -n "racksMismatch" clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractStickyAssignor.java
492:        private boolean racksMismatch(String consumer, TopicPartition tp) {
665:                        .filter(tp -> !rackInfo.racksMismatch(consumer, tp))
1023:                        } else if (!consumerSubscription.topics().contains(partition.topic()) || rackInfo.racksMismatch(consumer, partition)) {
1238:                if (consumer2AllPotentialTopics.get(consumer).contains(partition.topic()) && (rackInfo == null || !rackInfo.racksMismatch(consumer, partition))) {
```

```
$ cat -n clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractStickyAssignor.java | sed -n '659,714p'
   659	        // Reassign previously owned partitions, up to the expected number of partitions per consumer
   660	        private void assignOwnedPartitions() {
   661	
   662	            for (Map.Entry<String, List<TopicPartition>> consumerEntry : currentAssignment.entrySet()) {
   663	                String consumer = consumerEntry.getKey();
   664	                List<TopicPartition> ownedPartitions = consumerEntry.getValue().stream()
   665	                        .filter(tp -> !rackInfo.racksMismatch(consumer, tp))
   666	                        .sorted(Comparator.comparing(TopicPartition::partition).thenComparing(TopicPartition::topic))
   667	                        .collect(Collectors.toList());
   668	
   669	                List<TopicPartition> consumerAssignment = assignment.get(consumer);
   670	
   671	                for (TopicPartition doublyClaimedPartition : partitionsWithMultiplePreviousOwners) {
   672	                    if (ownedPartitions.contains(doublyClaimedPartition)) {
   673	                        log.error("Found partition {} still claimed as owned by consumer {}, despite being claimed by multiple "
   674	                                        + "consumers already in the same generation. Removing it from the ownedPartitions",
   675	                                doublyClaimedPartition, consumer);
   676	                        ownedPartitions.remove(doublyClaimedPartition);
   677	                    }
   678	                }
   679	
   680	                if (ownedPartitions.size() < minQuota) {
   681	                    // the expected assignment size is more than this consumer has now, so keep all the owned partitions
   682	                    // and put this member into the unfilled member list
   683	                    if (ownedPartitions.size() > 0) {
   684	                        consumerAssignment.addAll(ownedPartitions);
   685	                        assignedPartitions.addAll(ownedPartitions);
   686	                    }
   687	                    unfilledMembersWithUnderMinQuotaPartitions.add(consumer);
   688	                } else if (ownedPartitions.size() >= maxQuota && currentNumMembersWithOverMinQuotaPartitions < expectedNumMembersWithOverMinQuotaPartitions) {
   689	                    // consumer owned the "maxQuota" of partitions or more, and we're still under the number of expected members
   690	                    // with more than the minQuota partitions, so keep "maxQuota" of the owned partitions, and revoke the rest of the partitions
   691	                    currentNumMembersWithOverMinQuotaPartitions++;
   692	                    if (currentNumMembersWithOverMinQuotaPartitions == expectedNumMembersWithOverMinQuotaPartitions) {
   693	                        unfilledMembersWithExactlyMinQuotaPartitions.clear();
   694	                    }
   695	                    List<TopicPartition> maxQuotaPartitions = ownedPartitions.subList(0, maxQuota);
   696	                    consumerAssignment.addAll(maxQuotaPartitions);
   697	                    assignedPartitions.addAll(maxQuotaPartitions);
   698	                    allRevokedPartitions.addAll(ownedPartitions.subList(maxQuota, ownedPartitions.size()));
   699	                } else {
   700	                    // consumer owned at least "minQuota" of partitions
   701	                    // so keep "minQuota" of the owned partitions, and revoke the rest of the partitions
   702	                    List<TopicPartition> minQuotaPartitions = ownedPartitions.subList(0, minQuota);
   703	                    consumerAssignment.addAll(minQuotaPartitions);
   704	                    assignedPartitions.addAll(minQuotaPartitions);
   705	                    allRevokedPartitions.addAll(ownedPartitions.subList(minQuota, ownedPartitions.size()));
   706	                    // this consumer is potential maxQuota candidate since we're still under the number of expected members
   707	                    // with more than the minQuota partitions. Note, if the number of expected members with more than
   708	                    // the minQuota partitions is 0, it means minQuota == maxQuota, and there are no potentially unfilled
   709	                    if (currentNumMembersWithOverMinQuotaPartitions < expectedNumMembersWithOverMinQuotaPartitions) {
   710	                        unfilledMembersWithExactlyMinQuotaPartitions.add(consumer);
   711	                    }
   712	                }
   713	            }
   714	        }
```

## Developer hypothesis
Previously owned partitions are filtered by rack before the quota and unfilled-member bookkeeping in `assignOwnedPartitions()` runs. Worth checking how that filtering interacts with the bookkeeping the later round-robin phases rely on, when some owned partitions are on mismatched racks.
