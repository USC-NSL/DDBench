# Reproduce: Kafka #15170

## Prerequisites

- Docker. The JDK is in the `bug-bench/kafka` image; Gradle comes with the repository's wrapper.

## Step 1: Set up the case and open a shell

```bash
# from the repository root
./bench.sh setup kafka-15170-endless-rebalance-loop   # case repository at the buggy commit, built
./bench.sh shell kafka-15170-endless-rebalance-loop   # source at /workspace/src
```

Run the remaining steps inside the shell, from `/workspace/src`.

## Step 2: Build the project

```bash
./gradlew :clients:compileJava :clients:compileTestJava -x spotlessCheck -x checkstyleMain -x checkstyleTest --quiet
```

## Step 3: Inject and run the regression tests

Two test methods are injected into the existing test files:

1. `CooperativeStickyAssignorTest.testUniformSubscriptionTransferOwnershipListIsRight` -- verifies that the `partitionsTransferringOwnership` list is correctly populated when rack-aware rebalancing revokes partitions from consumers with mismatched racks.

2. `AbstractStickyAssignorTest` modification -- updates the existing `testRackAwarenessWithStaticMembership` test to use correct expected assignments for the cooperative assignor, which differs from the eager assignor due to the cooperative protocol's need to track ownership transfers.

```bash
./gradlew :clients:test --tests "CooperativeStickyAssignorTest.testUniformSubscriptionTransferOwnershipListIsRight" -x spotlessCheck -x checkstyleMain -x checkstyleTest
```

## Expected result (bug present)

The test FAILS because:
- `partitionsTransferringOwnership` has 0 entries instead of the expected 2 -- partitions revoked due to rack mismatch are not tracked for ownership transfer
- The `AbstractStickyAssignorTest` throws `IllegalStateException` because the unfilled members set is not properly cleared when the expected number of maxQuota consumers is reached

## Oracle verdict

`./bench.sh reproduce kafka-15170-endless-rebalance-loop` rebuilds the worktree and runs the oracle (`reproduce.sh`). It injects its own test method, `CooperativeStickyAssignorTest.testDDBenchOracleRackAwareOwnershipTransfer`: with rack-aware assignment enabled, consumer `c0` (rack 0) owns partitions 0-1 and `c1` (rack 1) owns partitions 2-3 of a 4-partition topic spread over 2 racks, so each consumer owns one partition on the other consumer's rack, and the cooperative sticky assignor computes the next assignment.

- **FAIL** (exit 1): the new assignment gives a partition to a consumer other than its current owner in this same rebalance, or to more than one consumer, or the assignor throws. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): every partition in the assignment goes to at most one consumer, and none goes to a consumer other than its current owner in this rebalance.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or `CooperativeStickyAssignorTest.java` is missing), or the test produced no JUnit report and no compilation error explains it.
