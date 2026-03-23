# hashicorp/raft #268: Shutdown() Deadlocks with Concurrent takeSnapshot()

| Field | Value |
|-------|-------|
| Project | [hashicorp/raft](https://github.com/hashicorp/raft) |
| Issue | [#268](https://github.com/hashicorp/raft/issues/268) |
| Language | Go |
| Category | Deadlock |

## Bug Summary

Calling `Raft.Shutdown()` can deadlock permanently if it races with a concurrent `takeSnapshot()` operation. The `runSnapshots` goroutine blocks waiting on `configurationsCh`, but the main Raft goroutine has already exited its run loop and will never process that request. `Shutdown()` waits for `runSnapshots` to finish, creating a circular dependency.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build test binary)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.21+

## What to Expect

**When the bug is present (FAIL):**
One or more runs out of 20 hang for over 15 seconds (deadlock in `Shutdown()`), and `timeout` kills the process.

**When the bug is fixed (PASS):**
All 20 runs complete `Shutdown()` within a few seconds.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
