# Reproduce: Kafka #15170

## Prerequisites

- Java 17 (JDK)
- Gradle (included via wrapper)
- Git

## Step 1: Clone and checkout

```bash
git clone https://github.com/apache/kafka.git
cd kafka
git checkout f0291ac74b88b988c4ab07c16286942838ba4556~1
```

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
