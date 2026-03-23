# Kvrocks #3356: Unbounded WAL Growth with Slow Replica

| Field | Value |
|-------|-------|
| Project | [Kvrocks](https://github.com/apache/kvrocks) |
| Issue | [#3356](https://github.com/apache/kvrocks/issues/3356) |
| Language | C++ |
| Category | Resource Leak (unbounded WAL growth) |

## Bug Summary

When a replica is slow to consume replication data, the master's replication feed thread blocks indefinitely. This prevents WAL compaction, causing the Write-Ahead Log to grow without bound. Under sustained write load, this leads to disk exhaustion.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify (requires sudo for iptables)
./reproduce.sh
```

## Prerequisites

- Git
- C++ compiler (GCC 7+ or Clang)
- CMake 3.16+
- `redis-cli` and `redis-benchmark` (from redis-tools package)
- `sudo` access (for iptables rules to simulate slow replica)

## What to Expect

**When the bug is present (FAIL):**
The master's WAL directory grows beyond 512MB under sustained write load with a throttled replica. The replication feed thread blocks on the slow consumer without any backpressure.

**When the bug is fixed (PASS):**
WAL growth is bounded. The feed thread applies backpressure or disconnects the slow replica instead of blocking indefinitely.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
