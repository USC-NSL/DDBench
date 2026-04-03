# Test Failure Output

Obtained by running `mvn -pl bookkeeper-server test -Dtest="LedgerRecovery2Test#testFirstWriterCannotCommitWriteAfter2ndWriterCloses" -Dmaven.repo.local=/workspace/.m2` against the buggy build.

## Output

```
[INFO] Running org.apache.bookkeeper.client.LedgerRecovery2Test
[ERROR] Tests run: 3, Failures: 3, Errors: 0, Skipped: 0, Time elapsed: 13.808 s <<< FAILURE! - in org.apache.bookkeeper.client.LedgerRecovery2Test
[ERROR] org.apache.bookkeeper.client.LedgerRecovery2Test.testFirstWriterCannotCommitWriteAfter2ndWriterCloses  Time elapsed: 5.513 s  <<< FAILURE!
java.lang.AssertionError: The write to b2 should have failed as it was fenced by the recovery read of step 7
	at org.junit.Assert.fail(Assert.java:88)
	at org.apache.bookkeeper.client.LedgerRecovery2Test.testFirstWriterCannotCommitWriteAfter2ndWriterCloses(LedgerRecovery2Test.java:473)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.base/java.lang.reflect.Method.invoke(Method.java:566)
	at org.junit.runners.model.FrameworkMethod$1.runReflectiveCall(FrameworkMethod.java:50)
	at org.junit.internal.runners.model.ReflectiveCallable.run(ReflectiveCallable.java:12)
	at org.junit.runners.model.FrameworkMethod.invokeExplosively(FrameworkMethod.java:47)
	at org.junit.internal.runners.statements.InvokeMethod.evaluate(InvokeMethod.java:17)
	at org.junit.runners.ParentRunner.runLeaf(ParentRunner.java:325)
	at org.junit.runners.BlockJUnit4ClassRunner.runChild(BlockJUnit4ClassRunner.java:78)
	at org.junit.runners.BlockJUnit4ClassRunner.runChild(BlockJUnit4ClassRunner.java:57)
	at org.junit.runners.ParentRunner$3.run(ParentRunner.java:290)
	at org.junit.runners.ParentRunner$1.schedule(ParentRunner.java:71)
	at org.junit.runners.ParentRunner.runChildren(ParentRunner.java:288)
	at org.junit.runners.ParentRunner.access$000(ParentRunner.java:58)
	at org.junit.runners.ParentRunner$2.evaluate(ParentRunner.java:268)
	at org.junit.runners.ParentRunner.run(ParentRunner.java:363)
	at org.apache.maven.surefire.junit4.JUnit4Provider.execute(JUnit4Provider.java:364)
	at org.apache.maven.surefire.junit4.JUnit4Provider.executeWithRerun(JUnit4Provider.java:272)
	at org.apache.maven.surefire.junit4.JUnit4Provider.executeTestSet(JUnit4Provider.java:237)
	at org.apache.maven.surefire.junit4.JUnit4Provider.invoke(JUnit4Provider.java:158)
	at org.apache.maven.surefire.booter.ForkedBooter.runSuitesInProcess(ForkedBooter.java:428)
	at org.apache.maven.surefire.booter.ForkedBooter.execute(ForkedBooter.java:162)
	at org.apache.maven.surefire.booter.ForkedBooter.run(ForkedBooter.java:562)
	at org.apache.maven.surefire.booter.ForkedBooter.main(ForkedBooter.java:548)

[... runs 2 and 3 identical failure omitted ...]

[INFO] Results:
[INFO] 
[ERROR] Failures: 
[ERROR] org.apache.bookkeeper.client.LedgerRecovery2Test.testFirstWriterCannotCommitWriteAfter2ndWriterCloses
[ERROR]   Run 1: LedgerRecovery2Test.testFirstWriterCannotCommitWriteAfter2ndWriterCloses:473 The write to b2 should have failed as it was fenced by the recovery read of step 7
[ERROR]   Run 2: LedgerRecovery2Test.testFirstWriterCannotCommitWriteAfter2ndWriterCloses:473 The write to b2 should have failed as it was fenced by the recovery read of step 7
[ERROR]   Run 3: LedgerRecovery2Test.testFirstWriterCannotCommitWriteAfter2ndWriterCloses:473 The write to b2 should have failed as it was fenced by the recovery read of step 7
[INFO] 
[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0
[INFO] 
[INFO] ------------------------------------------------------------------------
[INFO] BUILD FAILURE
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  33.542 s
```
