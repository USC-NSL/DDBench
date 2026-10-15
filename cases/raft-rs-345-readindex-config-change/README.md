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
# from the repository root
./bench.sh setup raft-rs-345-readindex-config-change        # build image + case repository, warm caches
./bench.sh reproduce raft-rs-345-readindex-config-change    # FAIL (exit 1) while the bug is present
./bench.sh shell raft-rs-345-readindex-config-change        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/raft-rs` image; see the top-level README).

## Build Notes

- The build compiles the test harness crate in `harness/` (`cd harness && cargo test --no-run`).

## What to Expect

**When the bug is present (FAIL):**
The ReadIndex request remains pending after a node is removed. The leader's `read_states` is empty even though the leader's self-ack is now sufficient for the reduced quorum.

**When the bug is fixed (PASS):**
The ReadIndex request completes immediately after the configuration change shrinks the quorum. The leader's `read_states` contains the completed read.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
