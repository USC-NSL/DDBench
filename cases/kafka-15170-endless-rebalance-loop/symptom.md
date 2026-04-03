# Symptom

The cooperative sticky consumer group assignor enters an infinite rebalance loop when rack-aware assignment is enabled and partitions need to be reassigned across consumers with mismatched rack placements.

## Observable behavior

- Consumer group enters an endless rebalancing loop that never converges
- Each rebalance attempt fails, triggering another rebalance attempt, creating an infinite loop
- The error occurs specifically when consumers have rack awareness enabled and some previously-owned partitions are on mismatched racks
- No partitions are successfully assigned during the loop

## Impact

- Consumer group stuck in endless rebalance loop
- No partitions are actually consumed during the loop
- Requires disabling rack-awareness or restarting all consumers to recover
- Affects any deployment using the cooperative sticky assignor with rack-aware consumer placement
