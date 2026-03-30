# Symptom

CooperativeStickyAssignor enters an infinite rebalance loop when rack-aware assignment is enabled and partitions need to be reassigned across consumers with mismatched rack placements.

## Observable behavior

- Consumer group enters an endless rebalancing loop that never converges
- The `AbstractStickyAssignor` throws `IllegalStateException` during assignment computation because the "unfilled members" set is not empty at the end of assignment, failing the internal correctness check
- The rebalance failure triggers another rebalance attempt, which hits the same bug, creating an infinite loop
- The error occurs specifically when consumers have rack awareness enabled and some previously-owned partitions are on mismatched racks
- The `partitionsTransferringOwnership` list is incorrect -- it fails to include partitions that were revoked due to rack mismatch during the cooperative adjustment phase
- This causes the cooperative consumer to not properly revoke partitions, further corrupting subsequent rebalance attempts

## Impact

- Consumer group stuck in endless rebalance loop
- No partitions are actually consumed during the loop
- Requires disabling rack-awareness or restarting all consumers to recover
- Affects any deployment using `CooperativeStickyAssignor` with rack-aware consumer placement
