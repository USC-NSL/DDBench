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
# from the repository root
./bench.sh setup kvrocks-2512-slaveof-deadlock        # build image + case repository, warm caches
./bench.sh reproduce kvrocks-2512-slaveof-deadlock    # FAIL (exit 1) while the bug is present
./bench.sh shell kvrocks-2512-slaveof-deadlock        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/kvrocks` image; see the top-level README).

## What to Expect

**When the bug is present (FAIL):**
The slave becomes unresponsive after rapid master switching. `PING` times out because the server is deadlocked.

**When the bug is fixed (PASS):**
The slave remains responsive and replies to `PING` after all master switches complete.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
