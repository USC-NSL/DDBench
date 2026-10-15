# Solution: Consul #12295

- **Issue:** https://github.com/hashicorp/consul/issues/12295
- **Fix commit:** [`24245edfcc9d56eb1033908c607f56b19f7d1360`](https://github.com/hashicorp/consul/commit/24245edfcc9d56eb1033908c607f56b19f7d1360)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/hashicorp/consul/pull/12565
- **Commit:** `24245edfcc9d56eb1033908c607f56b19f7d1360`

## Fix locus
- **Component:** Routine lifecycle manager (`lib/routine/`)
- **Files:**
  - `lib/routine/routine.go` (+16/-4) — adds `cancelCh <-chan struct{}` field to `routineTracker`; `running()` now returns `false` when either `stoppedCh` OR `cancelCh` is closed; `Start()` populates `cancelCh = ctx.Done()` (parent context's Done channel)
  - `lib/routine/routine_test.go` (+55/-0) — adds `TestManager_StopBlocking` regression test

## Root cause

`startACLReplication()` in `agent/consul/leader.go` checks `leaderRoutineManager.IsRunning(aclPolicyReplicationRoutineName)` before calling `Start()`. If `IsRunning()` returns `true`, it returns early without restarting the routines.

`IsRunning()` delegates to `routineTracker.running()`, which originally only checked `stoppedCh` — a channel closed when the goroutine's `execute()` wrapper exits. Cross-DC ACL replication RPCs are blocking calls that do not return promptly when their context is cancelled. When the leader context is cancelled (Raft steps down), the goroutine is blocked inside one of these RPCs. `stoppedCh` remains open for as long as the RPC is in flight (potentially minutes, as shown in production traces).

The race: `leaderLoop` runs in one goroutine. When leadership is lost (`stopCh` closes), the goroutine exits the `for` loop and the deferred `revokeLeadership()` runs — eventually calling `stopACLReplication()` → `Stop()`. However, the Consul server's leadership monitoring code immediately starts a **new** `leaderLoop` goroutine when the same server wins the next election. If this new goroutine reaches `startACLReplication()` → `IsRunning()` before the old goroutine's deferred `revokeLeadership()` has called `Stop()`, it sees the old routine as still running and returns early. The ACL replication routines are never restarted.

## Diagnosis chain

1. **Runtime observation:** Server logs show `stopping routine: routine="acl token replication"` (and policy, role) during `revokeLeadership`, but no corresponding `started routine` messages after the same server re-establishes leadership. ACL tokens created in the primary DC stop appearing in the secondary DC. The absence is silent — no error logs.
2. **Code path from symptom:** Search for where ACL replication is started: `startACLReplication()` in `agent/consul/leader.go`. It has an early-exit guard: `if s.leaderRoutineManager.IsRunning(aclPolicyReplicationRoutineName) { return }`. If this condition fires incorrectly, replication is never restarted.
3. **Narrowing to the lifecycle tracker:** `IsRunning()` delegates to `running()` in `lib/routine/routine.go`. `running()` checks only `stoppedCh`. `stoppedCh` is closed by `execute()` after the goroutine function returns — but ACL replication goroutines block on cross-DC RPCs and do not return immediately after context cancellation.
4. **Root cause confirmed:** There is a window between when the parent context is cancelled (leadership lost → `stopCh` → `leaderCtx.Done()` closed) and when `Stop()` is called (by `revokeLeadership()` in the old goroutine's deferred call). During this window, `running()` returns `true` (stoppedCh not closed), so `IsRunning()` returns `true`, and `startACLReplication()` skips restarting.
5. **Fix:** Add `cancelCh = ctx.Done()` (the parent context's Done channel, closed immediately when leadership is lost) to `routineTracker`. `running()` returns `false` as soon as `cancelCh` is closed, regardless of `stoppedCh`. This closes the race window.

## Fix description

`routineTracker` gains a `cancelCh <-chan struct{}` field set to `ctx.Done()` (the PARENT context passed to `Start()`, not the child `rtCtx`). The `running()` method is updated to return `false` if either `stoppedCh` (goroutine exited) OR `cancelCh` (parent context done) is closed. Because Go context cancellation is synchronous and immediate, `cancelCh` closes at the instant the parent context is cancelled — before any blocking RPCs have a chance to return. This makes `IsRunning()` report the correct lifecycle state from the moment the leadership context is done.

## How to apply

```bash
git checkout 24245edfcc9d56eb1033908c607f56b19f7d1360
```

## How to verify

Run `reproduce.sh` — should print `PASS: Bug is fixed`.
