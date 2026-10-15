# Code Investigation

## What was searched
The symptom describes an acknowledged entry disappearing after a second client recovers and closes the ledger while the original writer is still active. Searched for how the client-side recovery path reads entries from bookies, starting from the `isRecoveryRead` mode of `PendingReadOp`.

## What was found
```
$ grep -n "isRecoveryRead" bookkeeper-server/src/main/java/org/apache/bookkeeper/client/PendingReadOp.java
76:    final boolean isRecoveryRead;
309:            if (isRecoveryRead && numBookiesMissingEntry >= requiredBookiesMissingEntryForRecovery) {
428:            if (isRecoveryRead && (numBookiesMissingEntry >= requiredBookiesMissingEntryForRecovery)) {
461:                  boolean isRecoveryRead) {
468:        this.isRecoveryRead = isRecoveryRead;
571:        int flags = isRecoveryRead ? BookieProtocol.FLAG_HIGH_PRIORITY : BookieProtocol.FLAG_NONE;
591:            if (!isRecoveryRead) {
```

```
$ sed -n '566,604p' bookkeeper-server/src/main/java/org/apache/bookkeeper/client/PendingReadOp.java
    void sendReadTo(int bookieIndex, BookieId to, LedgerEntryRequest entry) throws InterruptedException {
        if (lh.throttler != null) {
            lh.throttler.acquire();
        }

        int flags = isRecoveryRead ? BookieProtocol.FLAG_HIGH_PRIORITY : BookieProtocol.FLAG_NONE;
        clientCtx.getBookieClient().readEntry(to, lh.ledgerId, entry.eId,
                                              this, new ReadContext(bookieIndex, to, entry), flags);
    }

    @Override
    public void readEntryComplete(int rc, long ledgerId, final long entryId, final ByteBuf buffer, Object ctx) {
        final ReadContext rctx = (ReadContext) ctx;
        final LedgerEntryRequest entry = rctx.entry;

        if (rc != BKException.Code.OK) {
            entry.logErrorAndReattemptRead(rctx.bookieIndex, rctx.to, "Error: " + BKException.getMessage(rc), rc);
            return;
        }

        heardFromHosts.add(rctx.to);
        heardFromHostsBitSet.set(rctx.bookieIndex, true);

        buffer.retain();
        if (entry.complete(rctx.bookieIndex, rctx.to, buffer)) {
            if (!isRecoveryRead) {
                // do not advance LastAddConfirmed for recovery reads
                lh.updateLastConfirmed(rctx.getLastAddConfirmed(), 0L);
            }
            submitCallback(BKException.Code.OK);
        } else {
            buffer.release();
        }

        if (numPendingEntries < 0) {
            LOG.error("Read too many values for ledger {} : [{}, {}].",
                    ledgerId, startEntryId, endEntryId);
        }
    }
```

## Developer hypothesis
Recovery reads reuse the regular read machinery (`sendReadTo()` / `readEntryComplete()`), with a handful of `isRecoveryRead`-specific branches. Worth checking whether the requests issued during recovery give the guarantees that ledger recovery depends on while the original writer may still be adding entries.
