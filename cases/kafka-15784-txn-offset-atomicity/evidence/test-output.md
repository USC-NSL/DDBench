# Test Output

Obtained by running `./gradlew :core:test --tests "kafka.coordinator.group.TxnOffsetAtomicityTest" -x spotlessCheck -x checkstyleMain -x checkstyleTest` against the buggy build.

## Output

```
> Task :core:test FAILED
kafka.coordinator.group.TxnOffsetAtomicityTest.testTxnOffsetAtomicityOnAppendException() failed, log available in /workspace/worktrees/kafka-15784-txn-offset-atomicity/core/build/reports/testOutput/kafka.coordinator.group.TxnOffsetAtomicityTest.testTxnOffsetAtomicityOnAppendException().test.stdout

TxnOffsetAtomicityTest > testTxnOffsetAtomicityOnAppendException() FAILED
    org.opentest4j.AssertionFailedError: FAIL: Atomicity violation detected (KAFKA-15784). Group retains stale pending offsets in memory after log append exception. prepareTxnOffsetCommit was called before appendRecords, and the failure callback was never invoked to clean up.
        at app//org.junit.jupiter.api.AssertionUtils.fail(AssertionUtils.java:38)
        at app//org.junit.jupiter.api.Assertions.fail(Assertions.java:134)
        at app//kafka.coordinator.group.TxnOffsetAtomicityTest.testTxnOffsetAtomicityOnAppendException(TxnOffsetAtomicityTest.scala:143)

1 test completed, 1 failed

> Task :core:test FAILED

BUILD FAILED in 2m 55s
```
