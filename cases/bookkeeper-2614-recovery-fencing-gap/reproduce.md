# Reproduction Procedure

## Quick start

```bash
cd cases/bookkeeper-2614-recovery-fencing-gap/
./setup.sh    # clone, checkout buggy commit, Maven build
./reproduce.sh  # inject test infrastructure, run test → PASS/FAIL
```

## What the reproduce script does

1. Resets `PendingReadOp.java` to the buggy-commit state.
2. Cherry-picks test infrastructure files from the fix commit: `MockBookies.java` (new), `MockLedgerData.java` (new), updated `MockBookieClient.java` and `MockClientContext.java`, and updated `LedgerRecovery2Test.java` with the new test.
3. Runs `testFirstWriterCannotCommitWriteAfter2ndWriterCloses` via Maven Surefire.
4. Checks Maven output for BUILD SUCCESS / test pass.

The test uses `CompletableFuture` barriers to precisely control the interleaving: w2 fences bookies b1 and b2 (ack quorum reached), performs recovery reads that see empty state, and closes the ledger. Then w1 writes to b3 (unfenced) and b2, reaching ack quorum. On the buggy commit, `PendingReadOp` does not carry the fencing flag in recovery reads, so b3 was never fenced by w2 and accepts w1's write after close. The test asserts w1 should get `BKLedgerFencedException` — but on the buggy code, the write succeeds → test failure.

## Expected output (bug present)

```
testFirstWriterCannotCommitWriteAfter2ndWriterCloses: FAILED
BUILD FAILURE

FAIL: Bug is present — recovery reads do not carry fencing flag; original writer can commit after recovery close
```

## Expected output (bug fixed)

```
Tests run: 1, Failures: 0, Errors: 0
BUILD SUCCESS

PASS: Bug is fixed
```
