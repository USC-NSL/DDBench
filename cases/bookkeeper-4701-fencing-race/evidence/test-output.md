# Test Output

Obtained by running `mvn -pl bookkeeper-server test -Dtest=HandleFactoryRaceTest -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip` against the buggy build.

## Output

```
[ERROR] Failures: 
[ERROR] org.apache.bookkeeper.bookie.HandleFactoryRaceTest.testConcurrentGetHandleReturnsSameInstance
[ERROR]   Run 1: HandleFactoryRaceTest.testConcurrentGetHandleReturnsSameInstance:151 Race condition detected: getHandle() returned different LedgerDescriptor instances 468 times out of 500 trials
[ERROR]   Run 2: HandleFactoryRaceTest.testConcurrentGetHandleReturnsSameInstance:151 Race condition detected: getHandle() returned different LedgerDescriptor instances 110 times out of 500 trials
[ERROR]   Run 3: HandleFactoryRaceTest.testConcurrentGetHandleReturnsSameInstance:151 Race condition detected: getHandle() returned different LedgerDescriptor instances 80 times out of 500 trials

[ERROR] Tests run: 1, Failures: 1, Errors: 0, Skipped: 0

BUILD FAILURE
```
