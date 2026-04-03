# Protocol Trace Logs: bookkeeper-2614-recovery-fencing-gap

## How this was obtained

Enabled DEBUG-level logging for the BookKeeper client (`org.apache.bookkeeper.client`) and bookie protocol handler (`org.apache.bookkeeper.proto`) during the two-writer recovery test. Logging was configured via `log4j.properties` in the test resources:

```
log4j.logger.org.apache.bookkeeper.client=DEBUG
log4j.logger.org.apache.bookkeeper.proto=DEBUG
```

## Evidence

```
2024-03-12T14:22:07.416Z DEBUG [BookKeeperClientWorker-1] ReadLastConfirmedOp - Ledger 0: sending LAC fence request to b1/0.0.0.0:3181, flags=0x06
2024-03-12T14:22:07.416Z DEBUG [BookKeeperClientWorker-1] ReadLastConfirmedOp - Ledger 0: sending LAC fence request to b2/0.0.0.0:3182, flags=0x06
2024-03-12T14:22:07.417Z DEBUG [BookKeeperClientWorker-1] ReadLastConfirmedOp - Ledger 0: sending LAC fence request to b3/0.0.0.0:3183, flags=0x06
2024-03-12T14:22:07.418Z DEBUG [BookKeeperClientWorker-1] ReadLastConfirmedOp - Ledger 0: got LAC fence response from b1/0.0.0.0:3181, rc=OK, lac=-1
2024-03-12T14:22:07.419Z DEBUG [BookKeeperClientWorker-1] ReadLastConfirmedOp - Ledger 0: got LAC fence response from b2/0.0.0.0:3182, rc=OK, lac=-1
2024-03-12T14:22:07.420Z INFO  [BookKeeperClientWorker-1] ReadLastConfirmedOp - Ledger 0: LAC fence quorum reached (2/2), lac=-1
2024-03-12T14:22:07.425Z DEBUG [BookKeeperClientWorker-1] LedgerRecoveryOp - Ledger 0: starting recovery reads from entry 0
2024-03-12T14:22:07.426Z DEBUG [BookKeeperClientWorker-1] PendingReadOp - Ledger 0 entry 0: sending read to b1/0.0.0.0:3181, flags=0x02
2024-03-12T14:22:07.426Z DEBUG [BookKeeperClientWorker-1] PendingReadOp - Ledger 0 entry 0: sending read to b2/0.0.0.0:3182, flags=0x02
2024-03-12T14:22:07.427Z DEBUG [BookKeeperClientWorker-1] PendingReadOp - Ledger 0 entry 0: sending read to b3/0.0.0.0:3183, flags=0x02
2024-03-12T14:22:07.428Z DEBUG [BookKeeperClientWorker-1] PendingReadOp - Ledger 0 entry 0: got response from b1/0.0.0.0:3181, rc=NoSuchEntry
2024-03-12T14:22:07.429Z DEBUG [BookKeeperClientWorker-1] PendingReadOp - Ledger 0 entry 0: got response from b2/0.0.0.0:3182, rc=NoSuchEntry
2024-03-12T14:22:07.430Z DEBUG [BookKeeperClientWorker-1] PendingReadOp - Ledger 0 entry 0: got response from b3/0.0.0.0:3183, rc=NoSuchEntry
2024-03-12T14:22:07.431Z DEBUG [BookKeeperClientWorker-1] LedgerRecoveryOp - Ledger 0: no entry found at 0, recovery complete
2024-03-12T14:22:07.432Z INFO  [BookKeeperClientWorker-1] LedgerRecoveryOp - Ledger 0: closing ledger with lac=-1, length=0
2024-03-12T14:22:07.433Z DEBUG [BookKeeperClientWorker-1] LedgerHandle - Ledger 0: writing close metadata, lac=-1, state=CLOSED
2024-03-12T14:22:07.435Z INFO  [BookKeeperClientWorker-1] LedgerHandle - Ledger 0: successfully closed
2024-03-12T14:22:07.440Z DEBUG [BookKeeperClientWorker-2] PendingAddOp - Ledger 0 entry 0: sending add to b1/0.0.0.0:3181
2024-03-12T14:22:07.440Z DEBUG [BookKeeperClientWorker-2] PendingAddOp - Ledger 0 entry 0: sending add to b2/0.0.0.0:3182
2024-03-12T14:22:07.441Z DEBUG [BookKeeperClientWorker-2] PendingAddOp - Ledger 0 entry 0: sending add to b3/0.0.0.0:3183
2024-03-12T14:22:07.442Z DEBUG [BookKeeperClientWorker-2] PendingAddOp - Ledger 0 entry 0: got response from b1/0.0.0.0:3181, rc=Fenced
2024-03-12T14:22:07.443Z DEBUG [BookKeeperClientWorker-2] PendingAddOp - Ledger 0 entry 0: got response from b2/0.0.0.0:3182, rc=Fenced
2024-03-12T14:22:07.444Z DEBUG [BookKeeperClientWorker-2] PendingAddOp - Ledger 0 entry 0: got response from b3/0.0.0.0:3183, rc=OK
2024-03-12T14:22:07.444Z INFO  [BookKeeperClientWorker-2] PendingAddOp - Ledger 0 entry 0: completed with rc=OK (ack quorum not met, but b3 accepted)
```

## What this tells a developer

Two groups of requests use different flags values. The Phase 1 LAC fence requests use `flags=0x06`, while the Phase 2 recovery read requests use `flags=0x02`. The delayed Phase 1 request to b3 never completed before recovery reads began, yet the recovery reads to b3 proceeded with `flags=0x02`. After the ledger was closed, b3 still accepted a write from the original writer (rc=OK) while b1 and b2 correctly rejected with rc=Fenced. This suggests that the flags value used in recovery reads may not be enforcing the same fencing behavior as the Phase 1 requests. Investigating how the bookie protocol handler interprets different flag combinations during read operations could reveal why b3 remained in a writable state throughout the recovery process.
