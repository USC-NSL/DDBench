# Test Output

Obtained by running `mvn test -Dtest="Zk4643RegressionTest#testOnlyCommittedTxnsPersistedBeforeEpochUpdate"` in the `zookeeper-server` directory against the buggy build.

## Output

```
[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0, Time elapsed: 1.609 s <<< FAILURE! - in org.apache.zookeeper.server.quorum.Zk4643RegressionTest
[ERROR] testOnlyCommittedTxnsPersistedBeforeEpochUpdate{File}  Time elapsed: 1.451 s  <<< FAILURE!
org.opentest4j.AssertionFailedError: expected: <data1> but was: <data2>
	at org.apache.zookeeper.server.quorum.Zk4643RegressionTest$1.converseWithFollower(Zk4643RegressionTest.java:117)
	at org.apache.zookeeper.server.quorum.Zab1_0Test.testFollowerConversation(Zab1_0Test.java:444)
	at org.apache.zookeeper.server.quorum.Zk4643RegressionTest.testOnlyCommittedTxnsPersistedBeforeEpochUpdate(Zk4643RegressionTest.java:39)

[ERROR] Failures: 
[ERROR]   Zk4643RegressionTest.testOnlyCommittedTxnsPersistedBeforeEpochUpdate:39->Zab1_0Test.testFollowerConversation:444 expected: <data1> but was: <data2>
[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0
```
