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
# from the repository root
./bench.sh setup kvrocks-3356-replication-wal        # build image + case repository, warm caches
./bench.sh reproduce kvrocks-3356-replication-wal    # FAIL (exit 1) while the bug is present
./bench.sh shell kvrocks-3356-replication-wal        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains, plus `redis-cli` and `python3`, are in the `bug-bench/kvrocks` image; see the top-level README). The oracle needs no root, iptables, `tc` or extra Docker capabilities, and uses only the default server configuration.

## What to Expect

**When the bug is present (FAIL):**
The replica is frozen with `SIGSTOP` and 64 MB is written to the master. For the full 90 s observation window, the master keeps the stalled replica attached, with its send queue stuck.

**When the bug is fixed (PASS):**
The master detaches the stalled replica within the window. After the replica resumes, it reconnects and catches up.

## Detailed Documentation

- [`symptom.md`](symptom.md): observable behavior and error messages
- [`reproduce.md`](reproduce.md): step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh): the oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
