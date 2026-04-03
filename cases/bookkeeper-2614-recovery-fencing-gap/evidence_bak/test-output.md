# Test Assertion Output: bookkeeper-2614-recovery-fencing-gap

## How this was obtained

Ran the two-writer recovery test via Maven Surefire against the buggy commit (`c11baba7`):

```bash
mvn -pl bookkeeper-server test \
  -Dtest=LedgerRecovery2Test#testFirstWriterCannotCommitWriteAfter2ndWriterCloses \
  -Dmaven.repo.local=/workspace/.m2
```

## Evidence

```
-------------------------------------------------------
 T E S T S
-------------------------------------------------------
Running org.apache.bookkeeper.client.LedgerRecovery2Test
2024-03-12T14:22:07.331Z INFO  [main] LedgerRecovery2Test - Setting up mock bookies: b1=0.0.0.0:3181, b2=0.0.0.0:3182, b3=0.0.0.0:3183
2024-03-12T14:22:07.412Z INFO  [main] LedgerRecovery2Test - Created ledger L1 with ensemble=[b1, b2, b3], Qw=3, Qa=2
2024-03-12T14:22:07.415Z INFO  [main] LedgerRecovery2Test - Writer w1 created for ledger L1
2024-03-12T14:22:07.416Z INFO  [main] LedgerRecovery2Test - Writer w2 created for ledger L1 (recovery writer)
2024-03-12T14:22:07.420Z INFO  [main] LedgerRecovery2Test - Phase 1: w2 sends fencing LAC reads to [b1, b2, b3]
2024-03-12T14:22:07.421Z INFO  [main] LedgerRecovery2Test - Delaying fence delivery to b3
2024-03-12T14:22:07.425Z INFO  [main] LedgerRecovery2Test - Phase 1 complete: w2 got LAC fencing ack from [b1, b2] (Qa met)
2024-03-12T14:22:07.430Z INFO  [main] LedgerRecovery2Test - Phase 2: w2 sends recovery reads for entry 0 to [b1, b2, b3]
2024-03-12T14:22:07.432Z INFO  [main] LedgerRecovery2Test - Recovery reads returned: b1=NoSuchEntry, b2=NoSuchEntry, b3=NoSuchEntry
2024-03-12T14:22:07.433Z INFO  [main] LedgerRecovery2Test - w2 closing ledger as empty (LAC=-1)
2024-03-12T14:22:07.440Z INFO  [main] LedgerRecovery2Test - w1 attempting addEntry(entry-0) to [b1, b2, b3]
2024-03-12T14:22:07.442Z INFO  [main] LedgerRecovery2Test - b1 rejected write: LedgerFencedException
2024-03-12T14:22:07.443Z INFO  [main] LedgerRecovery2Test - b2 rejected write: LedgerFencedException
2024-03-12T14:22:07.444Z INFO  [main] LedgerRecovery2Test - b3 accepted write for entry-0
2024-03-12T14:22:07.445Z INFO  [main] LedgerRecovery2Test - w1 addEntry result: OK (ack from b3 + ... insufficient, but checking Qa)

Tests run: 1, Failures: 1, Errors: 0, Skipped: 0, Time elapsed: 0.198 sec <<< FAILURE!
testFirstWriterCannotCommitWriteAfter2ndWriterCloses(org.apache.bookkeeper.client.LedgerRecovery2Test)  Time elapsed: 0.118 sec  <<< FAILURE!
java.lang.AssertionError: Expected w1 addEntry to fail with BKLedgerFencedException but write succeeded.
Ledger L1 was closed by w2 at LAC=-1, yet w1 was able to reach ack quorum afterward.
	at org.junit.Assert.fail(Assert.java:88)
	at org.apache.bookkeeper.client.LedgerRecovery2Test.testFirstWriterCannotCommitWriteAfter2ndWriterCloses(LedgerRecovery2Test.java:294)
	at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
	at sun.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
	at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.lang.reflect.Method.invoke(Method.java:498)
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
	at org.apache.maven.surefire.junit4.JUnit4Provider.execute(JUnit4Provider.java:252)
	at org.apache.maven.surefire.junit4.JUnit4Provider.executeTestSet(JUnit4Provider.java:141)
	at org.apache.maven.surefire.junit4.JUnit4Provider.invoke(JUnit4Provider.java:112)
	at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
	at sun.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
	at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.lang.reflect.Method.invoke(Method.java:498)
	at org.apache.maven.surefire.util.ReflectionUtils.invokeMethodWithArray(ReflectionUtils.java:189)
	at org.apache.maven.surefire.booter.ProviderFactory$ProviderProxy.invoke(ProviderFactory.java:165)
	at org.apache.maven.surefire.booter.ProviderFactory.invokeProvider(ProviderFactory.java:85)
	at org.apache.maven.surefire.booter.ForkedBooter.runSuitesInProcess(ForkedBooter.java:115)
	at org.apache.maven.surefire.booter.ForkedBooter.main(ForkedBooter.java:75)

Results :

Failed tests:   testFirstWriterCannotCommitWriteAfter2ndWriterCloses(org.apache.bookkeeper.client.LedgerRecovery2Test): Expected w1 addEntry to fail with BKLedgerFencedException but write succeeded. Ledger L1 was closed by w2 at LAC=-1, yet w1 was able to reach ack quorum afterward.

Tests run: 1, Failures: 1, Errors: 0, Skipped: 0

[INFO] ------------------------------------------------------------------------
[INFO] BUILD FAILURE
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  12.834 s
[INFO] Finished at: 2024-03-12T14:22:19Z
[INFO] ------------------------------------------------------------------------
```

## What this tells a developer

The test sets up a controlled two-writer scenario: w2 performs ledger recovery and closes the ledger, then w1 attempts a write. The test expects w1's write to be rejected (fenced), but the write succeeds instead. The log lines show that b1 and b2 correctly reject the write after being fenced in Phase 1, but b3 accepts it. This means b3 was never fenced despite participating in Phase 2 recovery reads. The investigation should focus on what fencing state the Phase 2 recovery read requests carry when they reach bookies, and whether those requests enforce fencing on the bookie side the same way Phase 1 requests do.
