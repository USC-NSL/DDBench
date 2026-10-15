# hashicorp/raft #517: Data Race Between runCandidate() and appendEntries()

| Field | Value |
|-------|-------|
| Project | [hashicorp/raft](https://github.com/hashicorp/raft) |
| Issue | [#517](https://github.com/hashicorp/raft/issues/517) |
| Language | Go |
| Category | Data Race |

## Bug Summary

A data race exists between the candidate goroutine and the append entries handler during leadership transfer operations. When leadership transfer is triggered, concurrent unsynchronized access to a shared boolean field causes the Go race detector to report a `WARNING: DATA RACE`. One goroutine writes the field when exiting candidate state, while another goroutine reads it while processing heartbeat (append entries) requests.

## Quick Start

```bash
# from the repository root
./bench.sh setup raft-517-candidate-appendentries-race        # build image + case repository, warm caches
./bench.sh reproduce raft-517-candidate-appendentries-race    # FAIL (exit 1) while the bug is present
./bench.sh shell raft-517-candidate-appendentries-race        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/raft` image; see the top-level README).

## Build Notes

- No build step. The oracle injects `inject_test.go` into package `raft` and runs it under the Go race detector; no external services are needed.

## What to Expect

**When the bug is present (FAIL):**
One or more runs out of 30 trigger the Go race detector, printing `WARNING: DATA RACE` and exiting with a non-zero code.

**When the bug is fixed (PASS):**
All 30 runs complete without any race detector warnings.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
