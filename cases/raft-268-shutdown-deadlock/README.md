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
# from the repository root
./bench.sh setup raft-268-shutdown-deadlock        # build image + case repository, warm caches
./bench.sh reproduce raft-268-shutdown-deadlock    # FAIL (exit 1) while the bug is present
./bench.sh shell raft-268-shutdown-deadlock        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/raft` image; see the top-level README).

## Build Notes

- hashicorp/raft is a library, so there is no build step. The oracle builds a standalone harness (`test_main.go`, kept outside the worktree) against `/workspace/src` through a `go.mod` `replace` directive.
- The harness runs an in-process Raft node; no external services are needed.

## What to Expect

**When the bug is present (FAIL):**
One or more runs out of 20 hang for over 15 seconds (deadlock in `Shutdown()`), and `timeout` kills the process.

**When the bug is fixed (PASS):**
All 20 runs complete `Shutdown()` within a few seconds.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
