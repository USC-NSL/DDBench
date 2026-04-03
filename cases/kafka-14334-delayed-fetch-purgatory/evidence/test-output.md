# Test Output

Obtained by running `./gradlew :core:test --tests "kafka.server.ReplicaFetcherThreadTest.testBug14334DelayedFetchPurgatoryOnFollower" -x spotlessCheck` against the buggy build.

## Output

```
> Task :core:test
kafka.server.ReplicaFetcherThreadTest.testBug14334DelayedFetchPurgatoryOnFollower() failed, log available in /workspace/worktrees/kafka-14334-delayed-fetch-purgatory/core/build/reports/testOutput/kafka.server.ReplicaFetcherThreadTest.testBug14334DelayedFetchPurgatoryOnFollower().test.stdout

Gradle Test Run :core:test > Gradle Test Executor 2 > ReplicaFetcherThreadTest > testBug14334DelayedFetchPurgatoryOnFollower() FAILED
    org.opentest4j.AssertionFailedError: Bug KAFKA-14334: ReplicaFetcherThread does not override doWork() to complete delayed fetch requests after follower replication. Consumers fetching from followers always wait fetch.max.wait.ms timeout. ==> expected: <true> but was: <false>
        at app//org.junit.jupiter.api.AssertionFailureBuilder.build(AssertionFailureBuilder.java:151)
        at app//org.junit.jupiter.api.AssertionFailureBuilder.buildAndThrow(AssertionFailureBuilder.java:132)
        at app//org.junit.jupiter.api.AssertTrue.failNotTrue(AssertTrue.java:63)
        at app//org.junit.jupiter.api.AssertTrue.assertTrue(AssertTrue.java:36)
        at app//org.junit.jupiter.api.Assertions.assertTrue(Assertions.java:210)
        at app//kafka.server.ReplicaFetcherThreadTest.testBug14334DelayedFetchPurgatoryOnFollower(ReplicaFetcherThreadTest.scala:1285)

1 test completed, 1 failed

> Task :core:test FAILED

BUILD FAILED in 1m 56s
```
