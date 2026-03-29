# Solution: BookKeeper #4701

## Fix
- **PR:** https://github.com/apache/bookkeeper/pull/4701
- **Commit:** `44607a0e31ee8f979211eb5a4ef424de2871b92e`

## Root cause

`HandleFactoryImpl.getHandle()` uses `ConcurrentLongHashMap.putIfAbsent()` but ignores the return value. When two threads (write thread on `BookieWriteThreadPool` and fencing thread on `BookieHighPriorityThread`) both call `getHandle()` simultaneously for a ledger not yet in the map, each creates a separate `LedgerDescriptor` object. Both `addEntry()` and `fenceAndLogInJournal()` synchronize on `LedgerDescriptor`, but since they obtained different instances, the synchronization provides no mutual exclusion. The write thread's fence check passes (its descriptor was never fenced), allowing the entry to be written after the ledger was fenced on the other descriptor.

## Fix description

Capture the return value of `putIfAbsent()`. If it returns a non-null value that differs from the locally created handle, another thread already inserted a handle for this ledger -- retry `getHandle()` to pick up the existing one. This is a 5-line change in a single file.

### Diff
```java
// Before (buggy):
handle = LedgerDescriptor.create(masterKey, ledgerId, ledgerStorage);
ledgers.putIfAbsent(ledgerId, handle);

// After (fixed):
handle = LedgerDescriptor.create(masterKey, ledgerId, ledgerStorage);
LedgerDescriptor storedValue = ledgers.putIfAbsent(ledgerId, handle);
// If it has been modified by other thread, use the previous one.
if (storedValue != null && storedValue != handle) {
    return getHandle(ledgerId, masterKey, journalReplay);
}
```

## How to apply
```bash
git checkout 44607a0e31ee8f979211eb5a4ef424de2871b92e
```

## File changed
- `bookkeeper-server/src/main/java/org/apache/bookkeeper/bookie/HandleFactoryImpl.java` (+5, -1)
