# Evidence: Test Failure Output

## Source
Maven Surefire test runner executing `LedgerRecovery2Test#testFirstWriterCannotCommitWriteAfter2ndWriterCloses`

## Command
```bash
mvn -pl bookkeeper-server test \
    -Dtest="LedgerRecovery2Test#testFirstWriterCannotCommitWriteAfter2ndWriterCloses" \
    -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip
```

## Output
```
[INFO] -------------------------------------------------------
[INFO]  T E S T S
[INFO] -------------------------------------------------------
[INFO] Running org.apache.bookkeeper.client.LedgerRecovery2Test

[ERROR] testFirstWriterCannotCommitWriteAfter2ndWriterCloses(org.apache.bookkeeper.client.LedgerRecovery2Test)
  Time elapsed: 0.387 s  <<< FAILURE!
java.lang.AssertionError: The write to b2 should have failed as it was fenced by the recovery read of step 7
	at org.junit.Assert.fail(Assert.java:89)
	at org.apache.bookkeeper.client.LedgerRecovery2Test.testFirstWriterCannotCommitWriteAfter2ndWriterCloses(LedgerRecovery2Test.java:472)

[INFO]
[INFO] Results:
[INFO]
[ERROR] Failures:
[ERROR]   LedgerRecovery2Test.testFirstWriterCannotCommitWriteAfter2ndWriterCloses:472
[INFO]
[INFO] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0
[INFO]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD FAILURE
[INFO] ------------------------------------------------------------------------
```

## Interpretation
The test expected writer w1's write to bookie b2 to fail with `BKLedgerFencedException` after b2 was contacted by w2's recovery read (step 7). Instead, the write succeeded, meaning b2 was NOT fenced by the recovery read. Writer w1 was able to reach ack quorum (b3 + b2) after w2 had already closed the ledger, resulting in a committed entry that the recovered ledger does not contain.
