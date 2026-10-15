# Solution: Kafka #15784

- **Issue:** https://issues.apache.org/jira/browse/KAFKA-15784
- **Fix commit:** [`e4249b69bda215d308ac5580a89fcc58ca054b97`](https://github.com/apache/kafka/commit/e4249b69bda215d308ac5580a89fcc58ca054b97)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix

- **PR:** https://github.com/apache/kafka/pull/14774 ("KAFKA-15784: Ensure atomicity of in memory update and write when transactionally committing offsets")
- **Commit:** `e4249b69bda215d308ac5580a89fcc58ca054b97`
- **Issue text:** KAFKA-15449 (PR #14370, transactional offset commit verification, KIP-890 part 1) "removed the locking around validating, updating state, and writing to the log transactional offset commits". Verification releases the group lock, so these steps are no longer atomic.

## Fix locus

- **Component:** group coordinator, transactional offset commit path (`GroupCoordinator`, `GroupMetadataManager`) and its use of `ReplicaManager` transaction verification
- **Files (gold.patch):**
  - `core/src/main/scala/kafka/coordinator/group/GroupCoordinator.scala` (+37/-8)
  - `core/src/main/scala/kafka/coordinator/group/GroupMetadataManager.scala` (+167/-137)
  - `core/src/main/scala/kafka/server/ReplicaManager.scala` (+299/-53)
  - `core/src/main/scala/kafka/coordinator/transaction/TransactionStateManager.scala` (+9/-9, named arguments only)

The upstream commit also changes five test files (`GroupCoordinatorTest`, `GroupMetadataManagerTest`, `ReplicaManagerTest`, `AbstractCoordinatorConcurrencyTest`, `KafkaApisTest`); they are not part of gold.patch. Because the fix changes `storeOffsets`' signature, core's existing test sources no longer compile with gold.patch alone. The case therefore builds `:core:jar` (not the whole build, whose `jmh-benchmarks` jar compiles core's tests), and the oracle compiles its test in a separate source set.

## Root cause

A transactional offset commit goes `GroupCoordinator.handleTxnCommitOffsets` → `doTxnCommitOffsets`, which takes the group lock, validates the commit (`validateOffsetCommit`: group not `Dead`, member and generation) and calls `GroupMetadataManager.storeOffsets`. `storeOffsets` updates the group in memory (`addProducerGroup`, `group.prepareTxnOffsetCommit`) and then calls `appendForGroup` → `ReplicaManager.appendRecords(..., transactionalId = ...)`.

With `transaction.partition.verification.enable=true`, `appendRecords` does not append when the producer has no ongoing transaction on the `__consumer_offsets` partition yet. It takes a `VerificationGuard`, sends a verification request through `AddPartitionsToTxnManager.verifyTransaction`, and returns. The records are appended later by `appendEntries`, called from the verification callback (wrapped by `KafkaRequestHandler.wrapAsyncCallback`, possibly on another request handler thread) without the group lock. The group lock is released as soon as `appendRecords` returns.

Validation and the in-memory update therefore happen before the transaction coordinator round trip, and the write after it, with the group lock released in between. If the group changes in that window, the write still happens with the stale validation. Examples: `DeleteGroups` marks the empty group `Dead` and removes it from the cache; unloading the offsets partition marks the group `Dead`, removes it and drops its producer-to-group mapping; offset deletion and rebalances (generation changes) have the same problem. The offset commit record is appended and the client gets `NONE`. `putCacheCallback` sees the group `Dead` and skips the cache update. When the commit marker arrives, `handleTxnCompletion` finds no group or no pending entry, so the committed offset never reaches the cache. Loading the partition replays the record and the marker and does produce the offset. The cache and the log have diverged.

## Diagnosis chain

1. **Runtime evidence:** the offset served by the live coordinator differs from the offset a reloaded coordinator (failover) serves. This happens only for transactional commits that overlap with a group event (deletion, partition unload/reload), and only when the commit is acknowledged with `NONE`. Plain (non-transactional) commits and non-overlapping transactional commits are consistent. The log contains the offset commit record and the commit marker, so the persisted side is complete and the cache is the one that is missing the offset.
2. **Narrowing the component:** the cache update for offset commits happens in `GroupMetadataManager.storeOffsets` (`prepareTxnOffsetCommit` before the append, `onTxnOffsetCommitAppend` / `failPendingTxnOffsetCommit` in `putCacheCallback` after it) and in `handleTxnCompletion` (on the marker). `putCacheCallback` skips a `Dead` group but still reports `NONE` for a successful append. So the append happened for a group that had already been deleted or unloaded, although `doTxnCommitOffsets` rejects `Dead` groups under the group lock.
3. **Code-level reasoning:** follow the append. `appendForGroup` passes `transactionalId` to `ReplicaManager.appendRecords`. With verification enabled, `appendRecords` takes the `notYetVerifiedEntriesPerPartition` branch, calls `verifyTransaction` and returns; the append runs later in the callback. Validation, `prepareTxnOffsetCommit` and the decision to write happen at request time under the group lock, but the write happens after an RPC round trip without it. Any group change in between is not seen by the write. The issue title, "ensure atomicity of in memory update and write", describes this.

## Fix description

The fix verifies first and then validates, updates and writes atomically:

- `GroupCoordinator.handleTxnCommitOffsets` calls the new `ReplicaManager.maybeStartTransactionVerificationForPartition(offsetTopicPartition, transactionalId, producerId, producerEpoch, NO_SEQUENCE, requestLocal, postVerificationCallback)`. Only when verification completes does `postVerificationCallback` call `doTxnCommitOffsets`. That method takes the group lock and runs `validateOffsetCommit`, then `storeOffsets`. A `Dead` group is now rejected (`COORDINATOR_NOT_AVAILABLE`, and the producer retries). Verification errors are mapped by the new `GroupMetadataManager.maybeConvertOffsetCommitError`.
- `storeOffsets` no longer takes `transactionalId`. It takes the offsets `TopicPartition` and an `Option[VerificationGuard]`, builds the records (`generateOffsetRecords`) and the callback (`createPutCacheCallback`), calls `prepareTxnOffsetCommit` / `prepareOffsetCommit` and then `appendForGroup`, all under the caller's group lock.
- `GroupMetadataManager.appendForGroup` calls the new `ReplicaManager.appendForGroup` (offsets topic only). It appends to the local log synchronously with the verification guards, so the write happens while the group lock is still held. `appendRecords` is refactored into shared helpers (`buildProducePartitionStatus`, `addCompletePurgatoryAction`, `maybeAddDelayedProduce`, `sendInvalidRequiredAcksResponse`) and the verification logic into `maybeStartTransactionVerificationForPartitions`.

Any fix that makes the validation, the in-memory update and the log write of a transactional offset commit atomic with respect to other group operations, while keeping verification, satisfies the oracle. For example, a fix that re-validates and prepares inside the post-verification append under the group lock would also pass.

## How to verify

```bash
./bench.sh validate-oracle kafka-15784-txn-offset-atomicity --runs 3   # buggy worktree FAILs, gold.patch PASSes -> SOUND
./bench.sh eval kafka-15784-txn-offset-atomicity --patch cases-solution/kafka-15784-txn-offset-atomicity/gold.patch
```
