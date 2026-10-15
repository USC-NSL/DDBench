# Symptom

After transactional offset commits overlap with other activity on their consumer group, the group coordinator serves committed offsets that differ from what is stored in `__consumer_offsets`. The difference shows up at the next coordinator failover: the new coordinator rebuilds the group from the log and serves different offsets than the old one did.

## Observable behavior

- An exactly-once application commits its consumer offsets through a transactional producer (`sendOffsetsToTransaction`) and then commits the transaction. The group is used only to store offsets (no active members, state `Empty`).
- Brokers run with default transaction settings (`transaction.partition.verification.enable=true`, the default in this version).
- While one of these offset commits is still being processed by the group coordinator, something else happens to the group on that coordinator:
  - an administrator deletes the group (`DeleteGroups`, for example `kafka-consumer-groups.sh --delete --group ...`), or
  - the coordinator unloads the group's `__consumer_offsets` partition and loads it again (leadership of the partition moves away and comes back).
- The producer receives a successful `TxnOffsetCommit` response and commits the transaction, but the coordinator then serves no committed offset for the partition (`OffsetFetch` returns offset `-1`).
- After a coordinator failover, the new coordinator rebuilds the group from `__consumer_offsets` and serves the committed offset. The offsets that consumers see change across the failover: the coordinator's in-memory offsets have diverged from the log.
- Without the overlapping group activity, the same commits are served correctly, both before and after a failover.
- No error is returned to any client; nothing reports a failure. Consumers can resume from the wrong position (duplicate processing, or skipped records after the next failover).
