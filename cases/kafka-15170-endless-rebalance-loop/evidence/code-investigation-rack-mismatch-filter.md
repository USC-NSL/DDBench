# Code Investigation

## What was searched
The symptom describes an infinite rebalance loop with the cooperative sticky assignor when rack-aware assignment is enabled. Investigated how rack-mismatched partitions are handled during the owned-partition reassignment phase.

## What was found
```
$ sed -n '664,670p' clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractStickyAssignor.java
                List<TopicPartition> ownedPartitions = consumerEntry.getValue().stream()
                        .filter(tp -> !rackInfo.racksMismatch(consumer, tp))
                        .sorted(Comparator.comparing(TopicPartition::partition).thenComparing(TopicPartition::topic))
                        .collect(Collectors.toList());
```

In `assignOwnedPartitions()`, previously owned partitions that are on a mismatched rack are silently filtered out (line 666). These filtered partitions are:
- NOT added to `allRevokedPartitions` (the revocation tracking set)
- NOT added to `assignedPartitions`
- NOT counted toward any consumer's assignment

This means they become unassigned but untracked — they fall into the "unassigned partitions" pool but the unfilled-members accounting doesn't expect them. The consumer that previously owned the partition still considers it owned (since it was never explicitly revoked), causing a mismatch between what the assignor computes and what the consumer reports in the next rebalance.

## Developer hypothesis
The `racksMismatch` filter in `assignOwnedPartitions()` and its relationship to the `allRevokedPartitions` and `assignedPartitions` tracking sets.
