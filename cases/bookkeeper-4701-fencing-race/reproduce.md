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
