# Verification: BookKeeper #4701

## Automated (reproduce.sh)

```bash
./reproduce.sh
```

- **FAIL:** At least one concurrent `getHandle()` pair returned different `LedgerDescriptor` instances, proving the race condition exists. The fencing thread and write thread would synchronize on different monitors, allowing writes to bypass the fence.
- **PASS:** All concurrent `getHandle()` pairs returned the same `LedgerDescriptor` instance. Fencing and writing share the same monitor, so the fence cannot be bypassed.

## Manual verification

After building, inject the test file and run:
```bash
mvn -pl bookkeeper-server test -Dtest=HandleFactoryRaceTest -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip
```

Check the Maven test output:
- `BUILD SUCCESS` with "PASS" in stdout means the bug is fixed.
- `BUILD FAILURE` or "FAIL" in stdout means the bug is present.
