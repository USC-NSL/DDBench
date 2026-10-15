# Runtime Evidence

Obtained by running `mvn -pl zookeeper-server test -Dtest=LearnerTest -Dmaven.repo.local=/workspace/.m2` against the buggy build.

## Output

```
Tests run: 7, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 2.648 s - in org.apache.zookeeper.server.quorum.LearnerTest
Tests run: 7, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS
```
