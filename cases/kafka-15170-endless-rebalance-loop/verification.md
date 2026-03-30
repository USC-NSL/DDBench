# Verification: Kafka #15170

```bash
# Inject regression tests and run them
./gradlew :clients:test --tests "CooperativeStickyAssignorTest.testUniformSubscriptionTransferOwnershipListIsRight" -x spotlessCheck -x checkstyleMain -x checkstyleTest
```

- **FAIL:** Test fails with an assertion error -- `partitionsTransferringOwnership` has 0 entries instead of 2. Partitions revoked due to rack mismatch are not tracked, and the unfilled members set is not cleared when the expected maxQuota count is reached. This is the bug causing infinite rebalance loops.
- **PASS:** Test passes -- `partitionsTransferringOwnership` correctly contains 2 entries for partitions that changed ownership due to rack-aware reassignment, and the unfilled members tracking is properly cleared.
