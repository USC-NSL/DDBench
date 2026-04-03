# Test Output

Obtained by running `./gradlew :clients:test --tests "CooperativeStickyAssignorTest.testBug15170OwnershipTransferRegression" -x spotlessCheck -x checkstyleMain -x checkstyleTest` against the buggy build.

## Output

```
> Task :clients:test FAILED
org.apache.kafka.clients.consumer.CooperativeStickyAssignorTest.testBug15170OwnershipTransferRegression() failed, log available in /workspace/worktrees/kafka-15170-endless-rebalance-loop/clients/build/reports/testOutput/org.apache.kafka.clients.consumer.CooperativeStickyAssignorTest.testBug15170OwnershipTransferRegression().test.stdout

Gradle Test Run :clients:test > Gradle Test Executor 1 > CooperativeStickyAssignorTest > testBug15170OwnershipTransferRegression() FAILED
    org.opentest4j.AssertionFailedError: Bug KAFKA-15170: partitionsTransferringOwnership is empty but should contain entries for partitions that changed ownership due to rack mismatch. Without this tracking, the cooperative protocol fails to revoke the correct partitions, causing infinite rebalance loops. ==> expected: <false> but was: <true>
        at app//org.junit.jupiter.api.AssertionFailureBuilder.build(AssertionFailureBuilder.java:151)
        at app//org.junit.jupiter.api.AssertionFailureBuilder.buildAndThrow(AssertionFailureBuilder.java:132)
        at app//org.junit.jupiter.api.AssertFalse.failNotFalse(AssertFalse.java:63)
        at app//org.junit.jupiter.api.AssertFalse.assertFalse(AssertFalse.java:36)
        at app//org.junit.jupiter.api.Assertions.assertFalse(Assertions.java:239)
        at app//org.apache.kafka.clients.consumer.CooperativeStickyAssignorTest.testBug15170OwnershipTransferRegression(CooperativeStickyAssignorTest.java:330)

1 test completed, 1 failed

> Task :clients:test FAILED

BUILD FAILED in 3s
```
