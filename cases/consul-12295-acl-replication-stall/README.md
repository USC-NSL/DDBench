# Consul #12295: ACL Replication Stall After Leadership Re-election

| Field | Value |
|-------|-------|
| Project | [Consul](https://github.com/hashicorp/consul) |
| Issue | [#12295](https://github.com/hashicorp/consul/issues/12295) |
| Fix PR | [#12565](https://github.com/hashicorp/consul/pull/12565) |
| Language | Go |
| Category | Logic error (routine lifecycle race between revokeLeadership and establishLeadership) |

## Bug Summary

When a Consul server in a secondary datacenter loses leadership and immediately regains it (same server re-elected), the ACL token, policy, and role replication routines are never restarted. The routine lifecycle tracker checks only whether the goroutine's own `stoppedCh` channel is closed to determine if the routine is "running". When the leader context is cancelled (Raft steps down), the blocking cross-DC replication RPCs do not return immediately, so `stoppedCh` remains open. If the new `leaderLoop` starts `establishLeadership` before `revokeLeadership` has had a chance to call `Stop()`, `IsRunning()` returns `true` for the cancelled-but-blocking routine, and `startACLReplication()` skips restarting the routines. The secondary DC is left with permanently stale ACL state until the next leadership change.

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## What to Expect

**When the bug is present (FAIL):**
`IsRunning()` returns `true` after the parent context is cancelled while the goroutine is blocking. The test fails with `"IsRunning returned true after parent context was cancelled"`.

**When the bug is fixed (PASS):**
`IsRunning()` returns `false` as soon as the parent context is cancelled, regardless of the goroutine's blocking state. New routines can be started immediately.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and log evidence
- [`setup.md`](setup.md) — Detailed setup instructions
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure
- [`verification.md`](verification.md) — Pass/fail verification criteria
