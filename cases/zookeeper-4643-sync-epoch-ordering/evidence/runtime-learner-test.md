# Runtime Evidence

Obtained by running `mvn -pl zookeeper-server test -Dtest=LearnerTest -Dmaven.repo.local=/workspace/.m2` against the buggy build.

## Output

```
Tests run: 7, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 2.648 s - in org.apache.zookeeper.server.quorum.LearnerTest
Tests run: 7, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS
```

The existing LearnerTest suite passes, but it does not cover the crash-during-sync scenario described in the symptom. The tests exercise normal learner synchronization paths but do not inject crashes between `startupWithoutServing()` and transaction persistence.
