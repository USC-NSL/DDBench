# BookKeeper #4701: Entry Loss Due to Fencing Race in HandleFactory

| Field | Value |
|-------|-------|
| Project | [Apache BookKeeper](https://github.com/apache/bookkeeper) |
| PR | [#4701](https://github.com/apache/bookkeeper/pull/4701) |
| Language | Java |
| Category | Race condition (data loss) |

## Bug Summary

`HandleFactoryImpl.getHandle()` uses `putIfAbsent()` but ignores the return value. When two threads (a write thread and a fencing/recovery thread) both call `getHandle()` simultaneously for a ledger that is not yet in the map, each creates a separate `LedgerDescriptor` object. Since `BookieImpl.addEntry()` and `fenceAndLogInJournal()` both synchronize on their respective `LedgerDescriptor` instance, the threads lock on different objects, allowing writes to bypass the fence. This causes entry loss during ledger recovery.

## Quick Start

```bash
# from the repository root
./bench.sh setup bookkeeper-4701-fencing-race        # build image + case repository, warm caches
./bench.sh reproduce bookkeeper-4701-fencing-race    # FAIL (exit 1) while the bug is present
./bench.sh shell bookkeeper-4701-fencing-race        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/bookkeeper` image; see the top-level README).

## Build Notes

- Maven builds only `bookkeeper-server` and its upstream modules, skipping tests and static checks; the first build takes roughly 5-10 minutes.

## What to Expect

**When the bug is present (FAIL):**
Concurrent `getHandle()` calls for the same ledger return different `LedgerDescriptor` objects in at least one trial. This means fencing and writing synchronize on different monitors, allowing writes to bypass the fence.

**When the bug is fixed (PASS):**
Concurrent `getHandle()` calls always return the same `LedgerDescriptor` instance, ensuring fencing and writing share the same monitor.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
