# Reproduce: Kafka #15784

## Step 1: Inject and run the regression test

The bug is in `GroupMetadataManager.storeOffsets` on the transactional offset commit path. It can be reproduced with a unit test that mocks `replicaManager.appendRecords` to throw an exception, then checks whether the group's in-memory state is properly cleaned up.

The test is injected into `core/src/test/scala/unit/kafka/coordinator/group/TxnOffsetAtomicityTest.scala` and exercises the transactional offset commit path directly:

```bash
cd kafka
./gradlew :core:test --tests "kafka.coordinator.group.TxnOffsetAtomicityTest" \
    -x spotlessCheck -x checkstyleMain -x checkstyleTest
```

The test does the following:
1. Creates a `GroupMetadataManager` with a mocked `ReplicaManager`.
2. Creates an empty consumer group and configures the mock to return a valid magic value for record generation.
3. Mocks `replicaManager.appendRecords` to throw a `RuntimeException` (simulating a log append failure that bypasses the callback).
4. Calls `storeOffsets` with a transactional offset commit (`producerId = 232`, `transactionalId = "txn-id"`).
5. After the exception propagates, checks whether `group.hasOffsets` and `group.hasPendingOffsetCommitsFromProducer(producerId)` still return true.

## Expected result (bug present)

The test fails because `group.hasOffsets` is true after the failed append. The call sequence is:

```
storeOffsets()
  -> group.prepareTxnOffsetCommit()    // mutates in-memory state
  -> appendForGroup()
    -> replicaManager.appendRecords()   // THROWS exception
  // putCacheCallback never invoked
  // group.failPendingTxnOffsetCommit() never called
  // group retains stale pending offsets
```

The `fail()` assertion fires with:

```
FAIL: Atomicity violation detected (KAFKA-15784).
Group retains stale pending offsets in memory after log append exception.
prepareTxnOffsetCommit was called before appendRecords, and the failure
callback was never invoked to clean up.
```

## Expected result (bug fixed)

The test passes. The fix refactors `storeOffsets` so that `prepareTxnOffsetCommit` is no longer called before `appendForGroup`. Instead, the in-memory state update is deferred into the callback, and the method uses a new `appendForGroup` API on `ReplicaManager` that handles the offsets topic atomically.
