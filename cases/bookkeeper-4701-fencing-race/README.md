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
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Java 11+ (JDK)
- Apache Maven 3.6+

## What to Expect

**When the bug is present (FAIL):**
Concurrent `getHandle()` calls for the same ledger return different `LedgerDescriptor` objects in at least one trial. This means fencing and writing synchronize on different monitors, allowing writes to bypass the fence.

**When the bug is fixed (PASS):**
Concurrent `getHandle()` calls always return the same `LedgerDescriptor` instance, ensuring fencing and writing share the same monitor.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
