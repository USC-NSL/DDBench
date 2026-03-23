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
# 1. Set up the codebase (clone, checkout buggy commit)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.21+

## What to Expect

**When the bug is present (FAIL):**
The `compactLogs` function computes a range where `maxLog < minLog`, meaning `DeleteRange` would be called with an invalid (reversed) range.

**When the bug is fixed (PASS):**
A bounds check prevents `DeleteRange` from being called with `maxLog < minLog`.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
