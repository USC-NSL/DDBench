# Kvrocks #2512: Deadlock When Switching Master Frequently via SLAVEOF

| Field | Value |
|-------|-------|
| Project | [Kvrocks](https://github.com/apache/kvrocks) |
| Issue | [#2512](https://github.com/apache/kvrocks/issues/2512) |
| Language | C++ |
| Category | Deadlock (mutex ordering violation) |

## Bug Summary

When two `SLAVEOF` commands are issued in quick succession pointing to different masters, the replication thread holds `WorkExclusivityGuard` while waiting for the old replication thread to stop, but the old thread is waiting to acquire `WorkConcurrencyGuard` held by a worker thread that is blocked on the join. This creates a circular dependency that permanently deadlocks the server.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git, C++ compiler, CMake
- redis-cli (for interacting with Kvrocks)

## What to Expect

**When the bug is present (FAIL):**
The slave becomes unresponsive after rapid master switching. `PING` times out because the server is deadlocked.

**When the bug is fixed (PASS):**
The slave remains responsive and replies to `PING` after all master switches complete.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
