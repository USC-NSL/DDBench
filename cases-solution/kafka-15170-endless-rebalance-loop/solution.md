# Solution: Kafka #15170

- **Issue:** https://issues.apache.org/jira/browse/KAFKA-15170
- **Fix commit:** [`f0291ac74b88b988c4ab07c16286942838ba4556`](https://github.com/apache/kafka/commit/f0291ac74b88b988c4ab07c16286942838ba4556)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix

- **PR:** https://github.com/apache/kafka/pull/13965
- **Commit:** `f0291ac74b88b988c4ab07c16286942838ba4556`

## Fix locus

- **Component:** Consumer group partition assignment (`clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractStickyAssignor.java`)
- **Files:**
  - `clients/src/main/java/org/apache/kafka/clients/consumer/internals/AbstractStickyAssignor.java` (+35/-8) -- Fixes two bugs in the rack-aware sticky assignment algorithm:
    1. Replaces `allRevokedPartitions` (Set) with `maybeRevokedPartitions` (Map<TopicPartition, String>) to track both the partition and the consumer it was revoked from, enabling correct ownership transfer detection
    2. Fixes unfilled-members tracking: properly increments `currentNumMembersWithOverMinQuotaPartitions` when a consumer reaches maxQuota, and clears the unfilled set once the expected count is reached
    3. Adds condition `currentNumMembersWithOverMinQuotaPartitions < expectedNumMembersWithOverMinQuotaPartitions` to prevent adding consumers to unfilled set when no more maxQuota slots are available
    4. Corrects `partitionsTransferringOwnership` logic: a partition transfers ownership only when it is revoked AND being assigned to a different consumer (not back to the same one)
  - `clients/src/test/java/org/apache/kafka/clients/consumer/CooperativeStickyAssignorTest.java` (+17) -- Adds `testUniformSubscriptionTransferOwnershipListIsRight` test
  - `clients/src/test/java/org/apache/kafka/clients/consumer/internals/AbstractStickyAssignorTest.java` (+20/-7) -- Updates `testRackAwarenessWithStaticMembership` with correct expected assignments for the cooperative assignor

## Root cause

Two related bugs in the rack-aware assignment logic of `AbstractStickyAssignor`:

**Bug 1: Missing ownership transfer tracking.** The assignor used `allRevokedPartitions` (a `Set<TopicPartition>`) to track revoked partitions but lost track of *which consumer* owned them. When checking whether a partition is transferring ownership (i.e., being assigned to a different consumer than its previous owner), the code only checked `allRevokedPartitions.contains(unassignedPartition)`. This was incorrect because during rack-aware rebalancing, a partition might be temporarily revoked from a consumer (due to rack mismatch) but then reassigned back to the same consumer. The code failed to distinguish this case from a true ownership transfer, leading to an incorrect `partitionsTransferringOwnership` list.

**Bug 2: Incorrect unfilled-members tracking.** During the round-robin assignment phase, the code tracked consumers at `minQuota` that might need an extra partition to reach `maxQuota`. However, it failed to increment `currentNumMembersWithOverMinQuotaPartitions` when a consumer's assignment count reached `maxQuota`. It also did not check whether the expected number of maxQuota consumers had already been reached before adding consumers to the unfilled set. This caused the unfilled-members set to be non-empty at the end of assignment, triggering the `IllegalStateException` correctness check and failing the rebalance.

## Diagnosis chain

1. **Observable symptom**: Consumer group enters infinite rebalance loop with `IllegalStateException` in `AbstractStickyAssignor`.
2. **Stack trace analysis**: Exception thrown at the end of `assignPartitions()` where the code asserts that `unfilledMembersWithExactlyMinQuotaPartitions` is empty.
3. **Code path**: `CooperativeStickyAssignor.assignPartitions()` -> `AbstractStickyAssignor.assignPartitions()` -> `GeneralAssignmentBuilder` -> round-robin assignment phase.
4. **Root cause 1 found**: `maybeRevokedPartitions` should be a Map tracking the previous consumer, not a Set. Without the consumer info, the ownership transfer check is wrong.
5. **Root cause 2 found**: `currentNumMembersWithOverMinQuotaPartitions` is never incremented when consumers reach maxQuota, and there is no guard against exceeding `expectedNumMembersWithOverMinQuotaPartitions`.
6. **Fix confirmed**: The PR addresses both bugs with targeted changes to the assignment builder.

## Fix description

The fix replaces `allRevokedPartitions` (`Set<TopicPartition>`) with `maybeRevokedPartitions` (`Map<TopicPartition, String>`) that tracks both the partition and the consumer it was revoked from. The ownership transfer check now correctly excludes partitions that are reassigned to their previous owner. Additionally, the fix properly increments the counter of consumers above minQuota when they reach maxQuota, and clears the unfilled set once the expected count is reached. An extra condition prevents adding consumers to the unfilled set when no more maxQuota slots are available.

## How to apply

```bash
git checkout f0291ac74b88b988c4ab07c16286942838ba4556
```

## How to verify

Run `reproduce.sh` -- should print `PASS: Bug is fixed`.
