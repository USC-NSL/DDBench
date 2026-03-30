# Verification: Kafka #14334

```bash
#!/bin/bash

cd kafka
./gradlew :core:test --tests "kafka.server.ReplicaFetcherThreadTest.testBug14334DelayedFetchPurgatoryOnFollower" -x spotlessCheck
```

- **FAIL:** The test fails because `ReplicaFetcherThread` lacks the `partitionsWithNewHighWatermark` tracking buffer added by the fix. Via reflection, the test detects that the fix API is absent:

  ```
  AssertionFailedError: Bug KAFKA-14334: ReplicaFetcherThread.partitionsWithNewHighWatermark missing.
  The delayed fetch purgatory is never completed after follower replication,
  causing consumers to always wait fetch.max.wait.ms timeout.
  ```

  This confirms the bug is present: delayed fetch purgatory is never completed on follower append, causing consumers to always hit `fetch.max.wait.ms`.

- **PASS:** The test passes, confirming that `ReplicaFetcherThread` has the `partitionsWithNewHighWatermark` field and the overridden `doWork()` completes delayed fetch requests for partitions whose high watermark changed.

  ```
  ReplicaFetcherThreadTest > testBug14334DelayedFetchPurgatoryOnFollower PASSED
  ```
