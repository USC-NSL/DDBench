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
# from the repository root
./bench.sh setup dragonfly-6687-replica-rdb-encoding        # build image + case repository, warm caches
./bench.sh reproduce dragonfly-6687-replica-rdb-encoding    # FAIL (exit 1) while the bug is present
./bench.sh shell dragonfly-6687-replica-rdb-encoding        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/dragonfly` image; see the top-level README).

## Build Notes

- Release build (`-DCMAKE_BUILD_TYPE=Release`); the binary is `build-opt/dragonfly`.
- The case container runs with 2 CPUs and an unconfined seccomp profile (`docker:` in `case.yaml`): Dragonfly sizes its thread pool from the CPU quota, and with more threads it refuses the scenario's `--maxmemory=512mb`.

## What to Expect

**When the bug is present (FAIL):**
The replica logs show "Unknown RDB string encoding" errors and `INFO replication` reports `master_link_status:down`. The replica never completes sync.

**When the bug is fixed (PASS):**
The replica successfully syncs with the master and `INFO replication` reports `master_link_status:up`.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
