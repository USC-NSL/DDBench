# Evidence: Two-Writer State Divergence After Recovery

## Source
Post-recovery state inspection of both writers and all three bookies, captured by querying ledger metadata and bookie entry state after the test scenario completes.

## Scenario Configuration
- Ledger L1, ensemble = [b1, b2, b3], Qw=3, Qa=2
- Writer w1 (original writer), Writer w2 (recovery writer)
- w1 successfully writes e0 and e1 (both acknowledged)
- w1 initiates write of e2

## Final State (buggy behavior)

### Writer w1 State
```
w1.getLastAddConfirmed() = 2       // w1 believes e2 was committed
w1.writeResult = SUCCESS            // asyncAddEntry callback received OK
Ensemble: {0: [b1, b2, b3]}        // single ensemble, no changes
```

### Writer w2 State (after recovery close)
```
w2.getLastAddConfirmed() = 1       // w2 closed ledger at e1
w2.ledgerMetadata.state = CLOSED
w2.ledgerMetadata.lastEntryId = 1
w2.ledgerMetadata.length = <length of e0 + e1>
Ensemble: {0: [b1, b2, b3]}
```

### Metadata Store (ZooKeeper/etcd)
```
Ledger L1:
  state: CLOSED
  lastEntryId: 1
  ensembles: {0: [b1, b2, b3]}
```

### Bookie Entry State
```
Bookie b1:
  L1 entries: {0: e0_data, 1: e1_data}
  L1 fenced: true (fenced by Phase 1 LAC read)

Bookie b2:
  L1 entries: {0: e0_data, 1: e1_data, 2: e2_data}
  L1 fenced: false (never fenced — Phase 1 LAC read failed/lost, Phase 2 read did not fence)

Bookie b3:
  L1 entries: {0: e0_data, 1: e1_data, 2: e2_data}
  L1 fenced: true (fenced by Phase 1 LAC read)
```

## Divergence Summary

| Entity | LastAddConfirmed | Has e2? | Fencing state |
|--------|-----------------|---------|---------------|
| w1 (original writer) | 2 | Yes (believes committed) | N/A |
| w2 (recovery writer) | 1 | No (never saw it) | N/A |
| Metadata store | 1 | No | CLOSED |
| Bookie b1 | - | No | Fenced |
| Bookie b2 | - | Yes (on disk) | **NOT fenced** |
| Bookie b3 | - | Yes (on disk) | Fenced |

## Impact
- Entry e2 exists on 2 of 3 bookies (b2, b3) which meets ack quorum, so w1 correctly considered it committed.
- However, the metadata store says the ledger is closed at entry 1. Any reader opening this ledger will read entries [e0, e1] and stop, never seeing e2.
- Entry e2 is silently lost. No error is recorded in metadata or logs. The data loss is invisible without comparing bookie-level state against metadata.
- Applications relying on the committed acknowledgment of e2 (e.g., a write-ahead log) will have inconsistent state.
