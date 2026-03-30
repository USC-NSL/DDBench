# Solution: Kafka #15784

## Fix
- **PR:** https://github.com/apache/kafka/pull/14774
- **Commit:** `e4249b69bda215d308ac5580a89fcc58ca054b97`

## Fix locus
- **Component:** Group coordinator offset management / ReplicaManager
- **Files:** `GroupMetadataManager.scala` (+167/-137), `GroupCoordinator.scala` (+37/-8), `ReplicaManager.scala` (+179/-36)

## Root cause

In `GroupMetadataManager.storeOffsets`, the transactional offset commit path calls `group.prepareTxnOffsetCommit(producerId, offsetMetadata)` to update the group's in-memory state BEFORE calling `appendForGroup` (which delegates to `replicaManager.appendRecords`) to persist the offset records to the `__consumer_offsets` topic log.

When `appendRecords` succeeds, the `putCacheCallback` is invoked, which calls `group.onTxnOffsetCommitAppend` to finalize the in-memory state. When `appendRecords` returns an error via the callback, `group.failPendingTxnOffsetCommit` rolls back the pending state. However, when `appendRecords` throws an exception (e.g., I/O error, storage failure), the callback is never invoked. The `prepareTxnOffsetCommit` mutation persists in memory with no corresponding rollback, causing the in-memory group state to diverge from the persisted transaction log state.

This violates the atomicity guarantee that should exist between in-memory and persisted state for transactional offset commits.

## Fix description

The fix is a large refactoring (+167/-137 in GroupMetadataManager alone) that:

1. **Separates record generation from state mutation**: Extracts `generateOffsetRecords` to build the MemoryRecords without touching group state, and `createPutCacheCallback` to create the callback that handles both success and failure of the log append. The in-memory state update (`group.onTxnOffsetCommitAppend` or `group.failPendingTxnOffsetCommit`) only happens inside the callback.

2. **Adds `appendForGroup` to ReplicaManager**: A new dedicated method for appending to the `__consumer_offsets` topic that accepts `VerificationGuard` objects for transaction verification. Unlike the general `appendRecords`, this method enforces that entries are only for the group metadata topic and handles verification guards.

3. **Adds transaction verification**: The `GroupCoordinator.doTxnCommitOffsets` flow now calls `maybeStartTransactionVerificationForPartition` on the ReplicaManager before proceeding with the offset commit. This verifies the transaction state before attempting any writes.

4. **Removes `transactionalId` from `storeOffsets`**: The transactional ID is no longer passed through `storeOffsets` to `appendRecords`. Instead, transaction verification happens at the coordinator level before `storeOffsets` is called.

5. **Adds `maybeConvertOffsetCommitError`**: A new helper method that maps verification and append errors to appropriate offset commit error codes.

## Diagnosis chain
1. **Runtime evidence:** After a storage failure during transactional offset commit, the coordinator may retain stale pending offsets in memory. On coordinator failover, the new coordinator reloads state from the log and the stale offsets disappear, revealing the inconsistency. Alternatively, a subsequent transaction commit/abort operates on incorrect in-memory state.
2. **Narrowing the component:** The transactional offset commit path goes through `GroupCoordinator.handleTxnCommitOffsets` -> `doTxnCommitOffsets` -> `GroupMetadataManager.storeOffsets`. The state mutation happens in `storeOffsets` where `group.prepareTxnOffsetCommit` is called before the log append.
3. **Code-level reasoning:** In `storeOffsets`, the call sequence is: (a) `addProducerGroup(producerId, groupId)` + `group.prepareTxnOffsetCommit(producerId, offsetMetadata)` under group lock, (b) `appendForGroup` which calls `replicaManager.appendRecords`. Step (a) mutates in-memory state. If step (b) throws an exception, the callback containing the rollback logic is never reached. The fix moves all state mutation into the callback so it only executes after the log append completes (success or failure).

## Key files
- `core/src/main/scala/kafka/coordinator/group/GroupMetadataManager.scala` (+167/-137) -- extract `generateOffsetRecords`, `createPutCacheCallback`; remove `transactionalId` from `storeOffsets`; add `maybeConvertOffsetCommitError`
- `core/src/main/scala/kafka/coordinator/group/GroupCoordinator.scala` (+37/-8) -- add transaction verification before offset commit; update `doTxnCommitOffsets` signature
- `core/src/main/scala/kafka/server/ReplicaManager.scala` (+179/-36) -- add `appendForGroup`, `maybeStartTransactionVerificationForPartition`; refactor `appendRecords` into helper methods
- `core/src/main/scala/kafka/coordinator/transaction/TransactionStateManager.scala` (+9/-9) -- minor parameter name alignment
- `core/src/test/scala/unit/kafka/server/ReplicaManagerTest.scala` (+86/-0) -- new tests for verification error handling
- `core/src/test/scala/unit/kafka/coordinator/group/GroupCoordinatorTest.scala` (+67/-32) -- new tests for txn offset commit error conversion
- `core/src/test/scala/unit/kafka/coordinator/group/GroupMetadataManagerTest.scala` (+45/-128) -- updated to use new `storeOffsets` and `appendForGroup` signatures

## How to apply
```bash
git checkout e4249b69bda215d308ac5580a89fcc58ca054b97
./gradlew jar -x test -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet
```
