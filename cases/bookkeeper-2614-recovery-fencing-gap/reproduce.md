# Reproduction Procedure

## Quick start

```bash
# from the repository root
./bench.sh setup bookkeeper-2614-recovery-fencing-gap      # case repository at the buggy commit, Maven build
./bench.sh reproduce bookkeeper-2614-recovery-fencing-gap  # inject test infrastructure, run test → PASS/FAIL
```

Inside `./bench.sh shell bookkeeper-2614-recovery-fencing-gap` (source at `/workspace/src`), the same oracle runs as `bash /bench/reproduce.sh`.

## What the reproduce script does

1. Rebuilds the worktree with `REBUILD.sh`; production code is never modified.
2. Injects the test-only files shipped in the case's `inject_test/` directory: `MockBookies.java`, `MockLedgerData.java`, `MockBookieClient.java`, `MockClientContext.java`, and `LedgerRecovery2Test.java` with the new test. Files already at those paths are saved and restored afterwards.
3. Runs `testFirstWriterCannotCommitWriteAfter2ndWriterCloses` via Maven Surefire.
4. Decides the verdict from the Surefire JUnit XML report for that test case.

The test uses `CompletableFuture` barriers to precisely control the interleaving: w2 fences bookies b1 and b2 (ack quorum reached), performs recovery reads that see empty state, and closes the ledger. Then w1 writes to b3 (unfenced) and b2, reaching ack quorum. On the buggy commit, `PendingReadOp` does not carry the fencing flag in recovery reads, so b3 was never fenced by w2 and accepts w1's write after close. The test asserts w1 should get `BKLedgerFencedException` — but on the buggy code, the write succeeds → test failure.

## Expected output (bug present)

```
testFirstWriterCannotCommitWriteAfter2ndWriterCloses: FAILED
BUILD FAILURE

FAIL: Bug is present — the original writer committed an entry after ledger recovery closed the ledger
```

## Expected output (bug fixed)

```
Tests run: 1, Failures: 0, Errors: 0
BUILD SUCCESS

PASS: Bug is fixed — the first writer cannot commit a write after recovery closed the ledger
```

## Oracle verdict

`./bench.sh reproduce bookkeeper-2614-recovery-fencing-gap` rebuilds the worktree and runs the oracle (`reproduce.sh`), which runs `LedgerRecovery2Test#testFirstWriterCannotCommitWriteAfter2ndWriterCloses` as described above. In its scripted interleaving a second writer recovers and closes the ledger at entry id 1 while the first writer's add of a third entry is still in flight.

- **FAIL** (exit 1): the first writer's add does not fail with `BKLedgerFencedException` within 200 ms (e.g. it is acknowledged), or either writer does not end with a single ensemble and last-add-confirmed 1. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): the first writer's add fails with `BKLedgerFencedException`, and both writers see a single ensemble with last-add-confirmed 1.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh`, `bookkeeper-server` or `inject_test/` is missing), an `inject_test/` file cannot be copied into the worktree, or the test produced no JUnit report and no compilation error explains it.
