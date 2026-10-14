# Kvrocks #3356: Replication Stalls Indefinitely on a Slow Replica

| Field | Value |
|-------|-------|
| Project | [Kvrocks](https://github.com/apache/kvrocks) |
| Issue | [#3356](https://github.com/apache/kvrocks/issues/3356) |
| Language | C++ |
| Category | Hang / liveness (replication stalls with no timeout, leading to WAL exhaustion) |

## Bug Summary

If a replica stops consuming the replication stream while its TCP connection stays open, the master never detaches it. The replica stays "connected" indefinitely (44 hours in production), with nothing logged. Meanwhile the master's WAL rotates past the replica's position. When the stall finally ends, a partial resync is no longer possible and a full resync is forced.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- C++ compiler (GCC 7+ or Clang)
- CMake 3.16+
- `redis-cli` (from redis-tools package)
- `python3`

## What to Expect

**When the bug is present (FAIL):**
The replica is frozen with `SIGSTOP` and 64 MB is written to the master. For the full 90 s observation window, the master keeps the stalled replica attached, with its send queue stuck.

**When the bug is fixed (PASS):**
The master detaches the stalled replica within the window. After the replica resumes, it reconnects and catches up.

## Detailed Documentation

- [`symptom.md`](symptom.md): observable behavior and error messages
- [`setup.md`](setup.md): detailed setup instructions
- [`reproduce.md`](reproduce.md): step-by-step reproduction procedure
- [`verification.md`](verification.md): pass/fail verification criteria
