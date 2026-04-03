# Evidence: Mock Bookie Fencing State Trace

## Source
Instrumented logging added to `MockBookies.readEntry()` and `MockBookies.addEntry()` to track fencing state during the two-writer recovery scenario.

## Trace (chronological order)

```
[Step 1] w1.asyncAddEntry("e2") initiated — sends to b1, b2, b3 (write quorum)
         w1 write to b1: BLOCKED by test barrier
         w1 write to b2: BLOCKED by test barrier
         w1 write to b3: BLOCKED by test barrier

[Step 2] w2 starts recovery — Phase 1: ReadLastConfirmed (fencing LAC read)
         w2 LAC read → b1: flags=FLAG_DO_FENCING|FLAG_HIGH_PRIORITY
           MockBookies.readEntry(b1, flags=0x06, L1, LAST_ADD_CONFIRMED)
           b1 fencing state BEFORE read: isFenced=false
           FLAG_DO_FENCING present in flags → calling ledger.fence()
           b1 fencing state AFTER read: isFenced=true
           Result: returns LAC entry (e1, lac=0)

[Step 3] w1 write e2 reaches b3 (unblocked)
         MockBookies.addEntry(b3, L1, entryId=2)
           b3 fencing state: isFenced=false → write ACCEPTED

[Step 4] w2 LAC read → b2: FAILS (simulated network loss/timeout)
           b2 fencing state: isFenced=false (UNCHANGED — never received fence)

[Step 5] w2 LAC read → b3: flags=FLAG_DO_FENCING|FLAG_HIGH_PRIORITY
           MockBookies.readEntry(b3, flags=0x06, L1, LAST_ADD_CONFIRMED)
           b3 fencing state BEFORE read: isFenced=false
           FLAG_DO_FENCING present in flags → calling ledger.fence()
           b3 fencing state AFTER read: isFenced=true
           Result: returns LAC entry (e1, lac=0)
         *** w2 has fencing ack quorum (b1 + b3) — Phase 1 complete ***

[Step 6] w2 Phase 2: Recovery reads — read entry e0 from b1
         MockBookies.readEntry(b1, flags=0x02, L1, entryId=0)
           *** FLAG_DO_FENCING (0x04) NOT SET — only FLAG_HIGH_PRIORITY (0x02) ***
           b1 already fenced from Phase 1, no effect
           Result: BKNoSuchLedgerExistsException (entry 0 not on b1 for this scenario)

[Step 7] w2 Phase 2: Recovery reads — read entry e0 from b2
         MockBookies.readEntry(b2, flags=0x02, L1, entryId=0)
           *** FLAG_DO_FENCING (0x04) NOT SET — only FLAG_HIGH_PRIORITY (0x02) ***
           b2 fencing state: isFenced=false (STILL UNFENCED)
           b2 was never reached by Phase 1 LAC fence, and Phase 2 read does NOT fence
           Result: BKNoSuchLedgerExistsException

[Step 8] w2 closes ledger — (Qw-Qa)+1 = 2 bookies confirmed no entry e0
         Ledger closed with lastEntryId=1, length based on e0+e1 only

[Step 9] w1 write e2 reaches b2 (unblocked)
         MockBookies.addEntry(b2, L1, entryId=2)
           b2 fencing state: isFenced=false → write ACCEPTED
         *** w1 now has ack quorum for e2: b3 (step 3) + b2 (step 9) ***
         *** e2 is COMMITTED by w1, but ABSENT from recovered ledger ***
```

## Key Finding

At Step 7, bookie b2 receives a recovery read but its `isFenced` state remains `false`. The read flags are `0x02` (`FLAG_HIGH_PRIORITY` only) — the `FLAG_DO_FENCING` bit (`0x04`) is not set. This allows b2 to accept w1's subsequent write at Step 9 even though b2 participated in recovery reads. The gap between fencing (Phase 1) and recovery reading (Phase 2) creates a window where a bookie can be read by recovery without being fenced.
