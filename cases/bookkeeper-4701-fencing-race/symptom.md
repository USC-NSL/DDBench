# Symptom

Entry loss during ledger recovery caused by a race condition in `HandleFactoryImpl.getHandle()`.

## Observable behavior

- When a client opens a ledger for recovery (fencing) while another client is writing, entries written after fencing completes may succeed silently instead of being rejected with `LedgerFencedException`.
- The fencing thread and the write thread obtain different `LedgerDescriptor` objects for the same ledger. Since both `addEntry()` and `fenceAndLogInJournal()` synchronize on the `LedgerDescriptor` instance, they lock on different monitors.
- The write thread's fence check (`handle.isFenced()`) reads from its own unfenced descriptor, allowing the write to proceed even though the ledger has been fenced on a different descriptor.
- The recovery reader then sees a LAC (Last Add Confirmed) that does not include the racing entry, causing data loss.

## Race sequence

| Write thread (BookieWriteThreadPool) | Fence thread (BookieHighPriorityThread) |
|---|---|
| `getHandle(ledgerId)` -> creates LedgerDescriptor A | |
| | `getHandle(ledgerId)` -> creates LedgerDescriptor B |
| A: `putIfAbsent(ledgerId, A)` succeeds | |
| | B: `putIfAbsent(ledgerId, B)` returns A (ignored!) |
| `synchronized(A)` { check fence -> not fenced } | `synchronized(B)` { setFenced() } |
| write entry (succeeds, bypasses fence) | read LAC (misses the racing entry) |

## Root cause location

`bookkeeper-server/src/main/java/org/apache/bookkeeper/bookie/HandleFactoryImpl.java`, method `getHandle()`: the return value of `ledgers.putIfAbsent(ledgerId, handle)` is discarded.
