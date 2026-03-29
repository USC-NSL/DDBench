# Verification Criteria

## FAIL (bug present)

`reproduce.sh` exits with code 1 and prints:

```
FAIL: Bug is present — recovery reads do not carry fencing flag; original writer can commit after recovery close
```

The test `testFirstWriterCannotCommitWriteAfter2ndWriterCloses` fails: writer w1 receives a successful write acknowledgment when it should have gotten a ledger-fenced exception. One bookie was not fenced by the recovery reads, allowing w1's write to succeed after w2 has already recovered and closed the ledger.

## PASS (bug fixed)

`reproduce.sh` exits with code 0 and prints:

```
PASS: Bug is fixed
```

The test passes: recovery reads now carry the fencing flag, so all bookies are fenced. When w1 attempts to write after recovery close, the bookie rejects the write, and w1 gets the expected fencing error.

## Verification invariant

The oracle verifies the correctness of the BookKeeper fencing protocol end-to-end:
1. Ledger recovery must fence bookies via reads (not just via explicit fence RPCs)
2. An entry acknowledged by the original writer before recovery closes cannot be silently truncated
3. The fencing from recovery reads prevents the original writer from reaching ack quorum after recovery close
