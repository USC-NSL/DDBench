# Evidence: PendingReadOp Flag Computation Trace

## Source
Targeted debug logging added at `PendingReadOp.sendReadTo()` to capture flag values computed for each read request during recovery.

## Instrumentation Point
In `PendingReadOp.sendReadTo()`, a log statement was added immediately after the flags computation:
```java
int flags = isRecoveryRead ? BookieProtocol.FLAG_HIGH_PRIORITY : BookieProtocol.FLAG_NONE;
LOG.debug("[DEBUG-TRACE] sendReadTo bookie={} ledger={} entry={} isRecoveryRead={} flags=0x{}", 
          to, lh.getId(), entry.getEntryId(), isRecoveryRead, Integer.toHexString(flags));
```

## Captured Output During Recovery

### Phase 1: ReadLastConfirmedOp (separate code path, not PendingReadOp)
```
[ReadLastConfirmedOp] readLac bookie=b1:3181 ledger=1 flags=0x06 (FLAG_HIGH_PRIORITY|FLAG_DO_FENCING)
[ReadLastConfirmedOp] readLac bookie=b2:3181 ledger=1 flags=0x06 (FLAG_HIGH_PRIORITY|FLAG_DO_FENCING)
[ReadLastConfirmedOp] readLac bookie=b3:3181 ledger=1 flags=0x06 (FLAG_HIGH_PRIORITY|FLAG_DO_FENCING)
```
Phase 1 LAC reads correctly include `FLAG_DO_FENCING` (0x04).

### Phase 2: PendingReadOp Recovery Reads
```
[DEBUG-TRACE] sendReadTo bookie=b1:3181 ledger=1 entry=0 isRecoveryRead=true flags=0x02
[DEBUG-TRACE] sendReadTo bookie=b2:3181 ledger=1 entry=0 isRecoveryRead=true flags=0x02
[DEBUG-TRACE] sendReadTo bookie=b3:3181 ledger=1 entry=0 isRecoveryRead=true flags=0x02
```
Phase 2 recovery reads have `isRecoveryRead=true` but flags are `0x02` (`FLAG_HIGH_PRIORITY` only). The `FLAG_DO_FENCING` bit (0x04) is absent.

## Flag Bit Breakdown
```
Expected for recovery read:  0x06 = 0b0110 = FLAG_HIGH_PRIORITY(0x02) | FLAG_DO_FENCING(0x04)
Actual for recovery read:    0x02 = 0b0010 = FLAG_HIGH_PRIORITY(0x02) only

Missing bit:                 0x04 = 0b0100 = FLAG_DO_FENCING
```

## Code Path
```
LedgerHandle.recover()
  → ReadLastConfirmedOp  [Phase 1 — sets FLAG_DO_FENCING correctly]
  → RecoveryReadOp.readEntries()
    → PendingReadOp(isRecoveryRead=true)
      → sendReadTo()
        → flags = FLAG_HIGH_PRIORITY   [Phase 2 — FLAG_DO_FENCING MISSING]
        → clientCtx.getBookieClient().readEntry(addr, lh.getId(), entryId, cb, ctx, flags, ...)
```

## Significance
The flag computation in `PendingReadOp.sendReadTo()` is the point where the fencing guarantee breaks. Recovery reads are treated as high-priority reads but not as fencing reads. Any bookie contacted only during Phase 2 (and missed during Phase 1) will not be fenced by the recovery process.
