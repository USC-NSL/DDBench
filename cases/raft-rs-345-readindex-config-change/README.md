# raft-rs #345: ReadIndex Stall After Quorum Shrinks on Config Change

| Field | Value |
|-------|-------|
| Project | [raft-rs](https://github.com/tikv/raft-rs) |
| Issue | [#345](https://github.com/tikv/raft-rs/issues/345) |
| Language | Rust |
| Category | Liveness (read stall) |

## Bug Summary

When the quorum size decreases due to a configuration change (node removal), pending ReadIndex requests are not re-evaluated against the new smaller quorum. Reads that already have enough acknowledgments under the new quorum remain stuck until the next heartbeat round, causing unnecessary read latency.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Rust toolchain (stable)
- protobuf-compiler

## What to Expect

**When the bug is present (FAIL):**
The ReadIndex request remains pending after a node is removed. The leader's `read_states` is empty even though the leader's self-ack is now sufficient for the reduced quorum.

**When the bug is fixed (PASS):**
The ReadIndex request completes immediately after the configuration change shrinks the quorum. The leader's `read_states` contains the completed read.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
