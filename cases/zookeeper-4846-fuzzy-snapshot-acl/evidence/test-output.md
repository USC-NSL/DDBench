# Test Output

Obtained by running `mvn test -Dtest="Zk4846Test#testCreateNodeRecoversPurgedACL" -DfailIfNoTests=false` in the `zookeeper-server` directory against the buggy build.

## Output

```
[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0, Time elapsed: 0.217 s <<< FAILURE! - in org.apache.zookeeper.server.Zk4846Test
[ERROR] testCreateNodeRecoversPurgedACL  Time elapsed: 0.21 s  <<< FAILURE!
org.opentest4j.AssertionFailedError: Bug present: RuntimeException when creating child under node with purged ACL: Failed to fetch acls for 2
	at org.apache.zookeeper.server.Zk4846Test.testCreateNodeRecoversPurgedACL(Zk4846Test.java:70)

[ERROR] Failures: 
[ERROR]   Zk4846Test.testCreateNodeRecoversPurgedACL:70 Bug present: RuntimeException when creating child under node with purged ACL: Failed to fetch acls for 2
[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0
```
