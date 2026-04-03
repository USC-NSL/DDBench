# Evidence: Recovery Phase Timeline

## Source
Detailed timeline reconstructed from DEBUG-level logging of `ReadLastConfirmedOp`, `PendingReadOp`, and `MockBookieClient` during the controlled two-writer test scenario.

## Timeline

```
T0  ─── w1 writes e0, e1 to [b1, b2, b3], both acknowledged (Qa=2) ───

T1  w1: asyncAddEntry(e2) → sends write requests to b1, b2, b3
        All three writes are in-flight but not yet delivered

T2  w2: recover(L1) starts
        w2 writes metadata: ledger L1 state → IN_RECOVERY
        w2 begins Phase 1: ReadLastConfirmedOp (fencing LAC reads)

T3  w2: Phase 1 LAC read → b1
        ReadLastConfirmedOp.readEntryComplete(b1, LAC, flags=0x06)
        b1 receives FLAG_DO_FENCING → b1.fence() called → b1 is now FENCED
        b1 responds: LAC = 1 (has entries e0, e1)

T4  w1: write e2 arrives at b3
        b3 is NOT YET FENCED (Phase 1 LAC read has not reached b3 yet)
        MockBookies.addEntry(b3, L1, e2) → b3.isFenced=false → ACCEPTED
        e2 now stored on b3

T5  w2: Phase 1 LAC read → b2 FAILS
        Network timeout / message loss simulated
        b2 never receives the fencing LAC request
        b2 fencing state: unchanged (isFenced=false)

T6  w2: Phase 1 LAC read → b3
        ReadLastConfirmedOp.readEntryComplete(b3, LAC, flags=0x06)
        b3 receives FLAG_DO_FENCING → b3.fence() called → b3 is now FENCED
        b3 responds: LAC = 1
        *** Phase 1 complete: ack quorum (b1, b3) fenced, b2 missed ***

T7  w2: Phase 2 begins — PendingReadOp recovery reads
        Recovery reads entries starting from LAC+1 = entry 2
        Actually reads from entry 0 in this scenario (empty LAC)
        
        w2 recovery read e0 → b1:
          PendingReadOp.sendReadTo(b1) flags = FLAG_HIGH_PRIORITY = 0x02
          *** FLAG_DO_FENCING (0x04) NOT included ***
          b1 already fenced → no effect
          b1 responds: NoSuchEntryException (e0 not on b1 in this path)

T8  w2: recovery read e0 → b2:
          PendingReadOp.sendReadTo(b2) flags = FLAG_HIGH_PRIORITY = 0x02
          *** FLAG_DO_FENCING (0x04) NOT included ***
          b2 fencing state: isFenced=false → REMAINS UNFENCED
          b2 responds: NoSuchEntryException
          
        (Qw-Qa)+1 = 2 bookies say no entry e0 → w2 concludes no entry exists
        beyond LAC. Ledger can be closed.

T9  w2: closes ledger L1 with lastEntryId=1
        Metadata updated: CLOSED, lastEntryId=1

T10 w1: write e2 arrives at b2
        b2 fencing state: isFenced=false
        MockBookies.addEntry(b2, L1, e2) → ACCEPTED
        w1 now has ack quorum for e2: b3 (T4) + b2 (T10)
        w1 callback: SUCCESS for e2

        *** DATA LOSS: e2 committed by w1 but absent from closed ledger ***
```

## Critical Window

The vulnerability exists between T6 and T8:
- At T6, Phase 1 completes with b2 unfenced
- At T8, Phase 2 recovery read reaches b2 but does NOT fence it
- If Phase 2 reads carried `FLAG_DO_FENCING`, b2 would have been fenced at T8
- Then at T10, b2 would reject w1's write, and w1 could not reach ack quorum
