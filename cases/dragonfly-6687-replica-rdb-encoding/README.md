# Dragonfly #6687: Replica Fails with "Unknown RDB String Encoding" During Tiered Storage Sync

| Field | Value |
|-------|-------|
| Project | [Dragonfly](https://github.com/dragonflydb/dragonfly) |
| Issue | [#6687](https://github.com/dragonflydb/dragonfly/issues/6687) |
| Language | C++ |
| Category | Replication error (RDB encoding corruption) |

## Bug Summary

When replicating from a Dragonfly master that has tiered storage enabled, the replica fails to sync with "Unknown RDB string encoding" errors. The replica enters a retry loop and never completes initial synchronization. This occurs because tiered entries are serialized at unsafe times, interleaving with snapshot generation and corrupting the RDB stream.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- C++ compiler (GCC 11+ or Clang 14+)
- CMake 3.16+
- Ninja build system
- `redis-cli` (from redis-tools package)

## What to Expect

**When the bug is present (FAIL):**
The replica logs show "Unknown RDB string encoding" errors and `INFO replication` reports `master_link_status:down`. The replica never completes sync.

**When the bug is fixed (PASS):**
The replica successfully syncs with the master and `INFO replication` reports `master_link_status:up`.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
