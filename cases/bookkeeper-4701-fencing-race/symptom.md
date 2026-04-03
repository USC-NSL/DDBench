# Symptom

Entry loss during ledger recovery caused by a race condition in the bookie.

## Observable behavior

- When a client opens a ledger for recovery (fencing) while another client is writing, entries written after fencing completes may succeed silently instead of being rejected with `LedgerFencedException`.
- The recovery reader then sees a LAC (Last Add Confirmed) that does not include the racing entry, causing data loss.
- The bug requires concurrent write and fence operations on the same ledger to manifest. A single-threaded sequence of fence-then-write correctly rejects the write.
