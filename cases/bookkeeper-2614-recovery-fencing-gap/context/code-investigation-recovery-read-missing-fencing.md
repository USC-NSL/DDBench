# Code Investigation

## What was searched
The symptom describes committed entries being silently truncated during ledger recovery. Investigated how recovery reads in `PendingReadOp` handle fencing compared to the initial `ReadLastConfirmedOp` that starts the recovery process.

## What was found
```
$ sed -n '566,575p' bookkeeper-server/src/main/java/org/apache/bookkeeper/client/PendingReadOp.java
    void sendReadTo(int bookieIndex, BookieId to, LedgerEntryRequest entry) throws InterruptedException {
        if (lh.throttler != null) {
            lh.throttler.acquire();
        }

        int flags = isRecoveryRead ? BookieProtocol.FLAG_HIGH_PRIORITY : BookieProtocol.FLAG_NONE;
        clientCtx.getBookieClient().readEntry(to, lh.ledgerId, entry.eId,
                                              this, new ReadContext(bookieIndex, to, entry), flags);
    }
```

For recovery reads (`isRecoveryRead=true`), `sendReadTo` only sets `FLAG_HIGH_PRIORITY` (0x0004). It does NOT set `FLAG_DO_FENCING` (0x0001) and passes `null` for the masterKey (via the default overload):

```
$ sed -n '150,152p' bookkeeper-server/src/main/java/org/apache/bookkeeper/proto/BookieClient.java
    default void readEntry(BookieId address, long ledgerId, long entryId,
                           ReadEntryCallback cb, Object ctx, int flags) {
        readEntry(address, ledgerId, entryId, cb, ctx, flags, null);  // masterKey = null
    }
```

In contrast, the `ReadLastConfirmedOp` that initiates recovery DOES use `FLAG_DO_FENCING` with the masterKey:

```
$ sed -n '88,95p' bookkeeper-server/src/main/java/org/apache/bookkeeper/client/ReadLastConfirmedOp.java
    public void initiateWithFencing() {
        for (int i = 0; i < currentEnsemble.size(); i++) {
            bookieClient.readEntry(currentEnsemble.get(i),
                                   ledgerId,
                                   BookieProtocol.LAST_ADD_CONFIRMED,
                                   this, i, BookieProtocol.FLAG_DO_FENCING,
                                   ledgerKey);
        }
    }
```

The bookie-side fencing check (in `PerChannelBookieClient`):

```
$ grep -n 'FLAG_DO_FENCING' bookkeeper-server/src/main/java/org/apache/bookkeeper/proto/PerChannelBookieClient.java
976:            if (((short) flags & BookieProtocol.FLAG_DO_FENCING) == BookieProtocol.FLAG_DO_FENCING) {
```

Only requests with `FLAG_DO_FENCING` trigger the bookie to fence the ledger.

## Developer hypothesis
The `PendingReadOp.sendReadTo()` flag and master-key construction compared to `ReadLastConfirmedOp.initiateWithFencing()`.
