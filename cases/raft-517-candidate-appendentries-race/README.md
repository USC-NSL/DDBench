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
One or more runs out of 30 trigger the Go race detector, printing `WARNING: DATA RACE` and exiting with a non-zero code.

**When the bug is fixed (PASS):**
All 30 runs complete without any race detector warnings.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
