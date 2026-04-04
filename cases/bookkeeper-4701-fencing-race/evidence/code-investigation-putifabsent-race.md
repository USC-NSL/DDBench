# Code Investigation

## What was searched
The symptom describes entries written after fencing succeeding silently instead of being rejected with `LedgerFencedException`. Investigated how `HandleFactoryImpl.getHandle()` manages concurrent access to `LedgerDescriptor` instances, since fencing is tracked per-instance.

## What was found
```
$ cat -n bookkeeper-server/src/main/java/org/apache/bookkeeper/bookie/HandleFactoryImpl.java
    54    public LedgerDescriptor getHandle(final long ledgerId, final byte[] masterKey, boolean journalReplay)
    55            throws IOException, BookieException {
    56        LedgerDescriptor handle = ledgers.get(ledgerId);
    57
    58        if (handle == null) {
    59            if (!journalReplay && recentlyFencedAndDeletedLedgers.getIfPresent(ledgerId) != null) {
    60                throw BookieException.create(BookieException.Code.LedgerFencedAndDeletedException);
    61            }
    62            handle = LedgerDescriptor.create(masterKey, ledgerId, ledgerStorage);
    63            ledgers.putIfAbsent(ledgerId, handle);
    64        }
    65
    66        handle.checkAccess(masterKey);
    67        return handle;
    68    }
```

At line 63, `ledgers.putIfAbsent(ledgerId, handle)` returns the existing `LedgerDescriptor` if one was concurrently inserted, but the return value is ignored. The method continues to use the locally created `handle` (line 62) rather than the one actually stored in the map.

The same pattern exists in `getReadOnlyHandle`:

```
    71    public LedgerDescriptor getReadOnlyHandle(final long ledgerId) throws IOException, Bookie.NoLedgerException {
    72        LedgerDescriptor handle = readOnlyLedgers.get(ledgerId);
    73
    74        if (handle == null) {
    75            handle = LedgerDescriptor.createReadOnly(ledgerId, ledgerStorage);
    76            readOnlyLedgers.putIfAbsent(ledgerId, handle);
    77        }
    78
    79        return handle;
    80    }
```

Fencing is tracked as per-instance state in `LedgerDescriptor`:

```
$ grep -n 'fenced\|setFenced\|isFenced' bookkeeper-server/src/main/java/org/apache/bookkeeper/bookie/LedgerDescriptor.java
67:    abstract boolean setFenced() throws IOException;
68:    abstract boolean isFenced() throws IOException, BookieException;
```

## Developer hypothesis
The `putIfAbsent` call site in `getHandle` and the variable used in subsequent statements. The same pattern in `getReadOnlyHandle`.
