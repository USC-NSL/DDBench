# Reproduce: BookKeeper #4701

## Step 1: Build the project
```bash
mvn -pl bookkeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```

## Step 2: Inject and run the race condition test

A Java test is injected into `bookkeeper-server/src/test/java/org/apache/bookkeeper/bookie/HandleFactoryRaceTest.java`. This test:

1. Creates a `HandleFactoryImpl` with a real `SortedLedgerStorage` (backed by temp directories)
2. Uses a `CyclicBarrier` to synchronize two threads calling `getHandle()` simultaneously for the same ledger ID (which does not yet exist in the map)
3. Checks whether both threads receive the same `LedgerDescriptor` instance
4. Repeats 500 times with fresh ledger IDs to maximize the chance of hitting the race window
5. Clears the internal map between iterations to force the `handle == null` code path

```bash
mvn -pl bookkeeper-server test -Dtest=HandleFactoryRaceTest -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip
```

## Expected result (bug present)

At least one iteration produces different `LedgerDescriptor` instances for the two threads. The test reports FAIL.

## Expected result (bug fixed)

All iterations return the same `LedgerDescriptor` instance. The test reports PASS.

## Oracle verdict

`./bench.sh reproduce bookkeeper-4701-fencing-race` rebuilds the worktree and runs the oracle (`reproduce.sh`). It injects its own test, `DDBenchOracleHandleFactoryRaceTest#testConcurrentGetHandleReturnsSameInstance` (backed by `DbLedgerStorage`), which runs the 500 trials of Step 2.

- **FAIL** (exit 1): in at least one trial the two threads calling `HandleFactoryImpl.getHandle()` for the same new ledger get different `LedgerDescriptor` instances, or a call throws or returns no handle within 5 s. A worktree that does not build, an oracle test that does not compile or is skipped, or a `HandleFactoryImpl` without the private `ledgers` map that the test clears by reflection between trials, is also FAIL.
- **PASS** (exit 0): in all 500 trials both threads get the same `LedgerDescriptor` instance.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh` or `bookkeeper-server` is missing), or the test produced no JUnit report and no compilation error explains it.
