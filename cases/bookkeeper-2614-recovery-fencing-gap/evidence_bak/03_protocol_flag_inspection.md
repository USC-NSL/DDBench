# Evidence: Protocol Flag Inspection

## Source
Runtime inspection of flags passed to `BookieClient.readEntry()` during recovery operations, using debug logging at the BookieProtocol layer.

## BookieProtocol Flag Constants
```
BookieProtocol.FLAG_NONE           = 0x00
BookieProtocol.FLAG_HIGH_PRIORITY  = 0x02
BookieProtocol.FLAG_DO_FENCING     = 0x04
BookieProtocol.FLAG_RECOVERY_ADD   = 0x08
```

## Observed Flags During Recovery

### Phase 1: ReadLastConfirmed (LAC fencing reads)
```
ReadLastConfirmedOp → BookieClient.readEntry(bookie, ledgerId, LAST_ADD_CONFIRMED, flags)
  flags = FLAG_DO_FENCING | FLAG_HIGH_PRIORITY = 0x06
  → Bookie receives FLAG_DO_FENCING → calls ledger.fence() → bookie is FENCED
```

### Phase 2: Recovery reads (PendingReadOp with isRecoveryRead=true)
```
PendingReadOp.sendReadTo() computes flags:
  int flags = isRecoveryRead ? BookieProtocol.FLAG_HIGH_PRIORITY : BookieProtocol.FLAG_NONE;
  → flags = FLAG_HIGH_PRIORITY = 0x02

BookieClient.readEntry(bookie, ledgerId, entryId, flags)
  flags = 0x02 (FLAG_HIGH_PRIORITY only)
  → Bookie receives read WITHOUT FLAG_DO_FENCING → does NOT call ledger.fence()
  → Bookie remains in its current fencing state (fenced or unfenced)
```

### Phase 2: Recovery write-back (PendingAddOp with isRecoveryAdd=true)
```
PendingAddOp → BookieClient.addEntry(bookie, ledgerId, entryId, data, options)
  options includes FLAG_RECOVERY_ADD = 0x08
  → Recovery adds bypass fencing check (by design — recovery writer must be able to write)
```

## Analysis

The protocol has three distinct operations during recovery:
1. **LAC fencing read** (Phase 1) — carries `FLAG_DO_FENCING`, fences the bookie
2. **Recovery read** (Phase 2) — carries only `FLAG_HIGH_PRIORITY`, does NOT fence
3. **Recovery write-back** (Phase 2) — carries `FLAG_RECOVERY_ADD`, bypasses fencing

If a bookie misses the Phase 1 LAC fencing read (network partition, delay, or failure), Phase 2 recovery reads do not compensate by fencing it. This means a bookie can participate in the recovery read quorum without being fenced, leaving a window for the original writer to reach ack quorum through that unfenced bookie.

## Bookie-Side Read Handler Logic
```
readEntry(flags, ledgerId, entryId):
  if (flags & FLAG_DO_FENCING) != 0:
    ledgerData.fence()     // <-- only happens if FLAG_DO_FENCING is set
  return ledgerData.getEntry(entryId)
```

When `FLAG_DO_FENCING` is absent, the read handler returns the entry without any side effects on fencing state. The bookie has no way to know this is a recovery read versus a normal read.
