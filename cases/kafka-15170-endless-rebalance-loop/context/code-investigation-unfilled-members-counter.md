# Code Investigation

## What was searched
Investigated the unfilled-members counter logic in the constrained assignment builder, looking for how `currentNumMembersWithOverMinQuotaPartitions` and `expectedNumMembersWithOverMinQuotaPartitions` interact with the unfilled member lists.

## What was found
```
$ sed -n '690,695p' clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractStickyAssignor.java
                    currentNumMembersWithOverMinQuotaPartitions++;
                    if (currentNumMembersWithOverMinQuotaPartitions == expectedNumMembersWithOverMinQuotaPartitions) {
                        unfilledMembersWithExactlyMinQuotaPartitions.clear();
                    }
```

When `currentNumMembersWithOverMinQuotaPartitions` reaches `expectedNumMembersWithOverMinQuotaPartitions`, the entire `unfilledMembersWithExactlyMinQuotaPartitions` list is cleared (line 693). This is intended to stop assigning beyond maxQuota, but when combined with the rack-mismatch filtering:

```
$ sed -n '582,586p' clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractStickyAssignor.java
        private final Set<TopicPartition> allRevokedPartitions;

        // the consumers which may still be assigned one or more partitions to reach expected capacity
        private final List<String> unfilledMembersWithUnderMinQuotaPartitions;
        private final LinkedList<String> unfilledMembersWithExactlyMinQuotaPartitions;
```

`allRevokedPartitions` is a `Set<TopicPartition>` — it tracks which partitions were revoked but not which consumer they were revoked from. When the `assignNewPartition` method checks `allRevokedPartitions.contains(unassignedPartition)` (line 806), it marks the partition as transferring ownership. But because the rack-mismatched partitions were dropped without being tracked, the unfilled member counts don't add up, and the algorithm either throws `IllegalStateException` or produces an assignment that triggers another rebalance.

## Developer hypothesis
The `expectedNumMembersWithOverMinQuotaPartitions` calculation and its interaction with the `unfilledMembersWithExactlyMinQuotaPartitions` clear-on-threshold logic in the context of rack-filtered partition counts.
