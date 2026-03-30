# Verification: Kafka #15784

```bash
cd kafka
./gradlew :core:test --tests "kafka.coordinator.group.TxnOffsetAtomicityTest" \
    -x spotlessCheck -x checkstyleMain -x checkstyleTest
```

- **FAIL:** The test fails because after a log append exception during a transactional offset commit, `group.hasOffsets` returns true and `group.hasPendingOffsetCommitsFromProducer(producerId)` returns true. The in-memory group state was mutated by `prepareTxnOffsetCommit` before the append, and the failure callback was never invoked to clean up. This confirms the atomicity violation.

  ```
  FAIL: Atomicity violation detected (KAFKA-15784).
  Group retains stale pending offsets in memory after log append exception.
  ```

- **PASS:** The test passes, confirming that the in-memory group state is unchanged after a failed append. The fix ensures state updates only happen in the append callback, maintaining atomicity between in-memory and persisted state.

  ```
  TxnOffsetAtomicityTest > testTxnOffsetAtomicityOnAppendException PASSED
  ```
