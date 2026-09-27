# Runtime Evidence

Obtained by running `mvn -pl zookeeper-server test -Dtest=DataTreeTest -Dmaven.repo.local=/workspace/.m2` against the buggy build.

## Output

```
Tests run: 19, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 0.363 s - in org.apache.zookeeper.server.DataTreeTest
Tests run: 19, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS
```

The existing DataTreeTest suite passes but does not cover the fuzzy snapshot recovery scenario where a `createNode` replay encounters a `NodeExistsException` for a node whose ACL reference has become stale after `aclCache.purgeUnused()`.
