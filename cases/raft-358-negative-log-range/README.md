# hashicorp/raft #358: Negative Log Compaction Range After Snapshot

| Field | Value |
|-------|-------|
| Project | [hashicorp/raft](https://github.com/hashicorp/raft) |
| Issue | [#358](https://github.com/hashicorp/raft/issues/358) |
| Language | Go |
| Category | Data corruption / Logic error |

## Bug Summary

After a snapshot is taken, the log compaction step computes a range for `DeleteRange` where the maximum index can be less than the minimum index (e.g., "Compacting logs from 26108 to 6079"). This happens when the snapshot's last included index is behind the log store's first index. Depending on the log store implementation, this invalid range can cause errors, panics, or silent data corruption.

## Quick Start

```bash
# from the repository root
./bench.sh setup raft-358-negative-log-range        # build image + case repository, warm caches
./bench.sh reproduce raft-358-negative-log-range    # FAIL (exit 1) while the bug is present
./bench.sh shell raft-358-negative-log-range        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/raft` image; see the top-level README).

## Build Notes

- hashicorp/raft is a library, so there is no binary to build; the oracle runs an injected Go test.

## What to Expect

**When the bug is present (FAIL):**
The `compactLogs` function computes a range where `maxLog < minLog`, meaning `DeleteRange` would be called with an invalid (reversed) range.

**When the bug is fixed (PASS):**
A bounds check prevents `DeleteRange` from being called with `maxLog < minLog`.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
