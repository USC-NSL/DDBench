# Reproduce: Consul #12295

## Prerequisites

- Docker. The Go toolchain is in the `bug-bench/consul` image.

## Step 1: Set up the codebase

```bash
# from the repository root
./bench.sh setup consul-12295-acl-replication-stall
```

This creates the case repository at the buggy commit (`/workspace/src` inside the container) and builds it.

## Step 2: Run the reproduction test

```bash
./bench.sh reproduce consul-12295-acl-replication-stall   # from the repository root
bash /bench/reproduce.sh                                  # or inside ./bench.sh shell consul-12295-acl-replication-stall
```

The script injects a test into `lib/routine/` and runs:

```bash
go test -v -run '^TestManager_IsRunningAfterParentContextCancel$' -count=1 -timeout 60s ./lib/routine/
```

## What the test does

The test simulates the race window between `revokeLeadership()` and `establishLeadership()` that occurs when the same server quickly loses and regains leadership:

1. A routine (`acl-policy-replication`) is started with a *parent context* (`leaderCtx`), mimicking how `startACLReplication()` registers the ACL replication goroutines.
2. The routine simulates a blocking cross-DC RPC by waiting on an `unblock` channel after its context is cancelled.
3. The parent context is cancelled (`leaderCancel()`), simulating Raft stepping down (the `stopCh` channel closing in `leaderLoop`).
4. **Without calling `Stop()` first** (the race window: `revokeLeadership()` hasn't run yet), the test calls `IsRunning("acl-policy-replication")`.
5. It asserts the result is `false` — the routine's leadership term is over, so it should be treated as not running regardless of whether the goroutine has exited.

## Expected result (bug present)

```
--- FAIL: TestManager_IsRunningAfterParentContextCancel (...)
    routine_test.go:NN: IsRunning returned true after parent context was cancelled
        while goroutine is still blocking on a long-running call. ...
FAIL
FAIL: Bug is present — IsRunning() still reports true after the parent context was cancelled
```

## Expected result (bug fixed)

```
--- PASS: TestManager_IsRunningAfterParentContextCancel (...)
PASS
PASS: Bug is fixed — IsRunning() returns false once the parent context is cancelled
```

## Oracle verdict

`./bench.sh reproduce consul-12295-acl-replication-stall` rebuilds the worktree and runs the oracle (`reproduce.sh`), which injects the test from `inject_test.go` into `lib/routine/` as `TestDDBenchOracleIsRunningAfterParentCancel`:

- **FAIL** (exit 1): the test fails or times out (60 s): after a routine's parent context is cancelled while the routine is still blocked, `IsRunning()` still reports it as running, or a new routine under the same name then does not start. A worktree that does not build, or an oracle test that does not compile or is skipped, is also FAIL.
- **PASS** (exit 0): `IsRunning()` reports `false` right after the parent context is cancelled, and a new routine under the same name starts and is reported as running.
- **ERROR** (exit 2): the case is not set up (`REBUILD.sh`, the `lib/routine` package or `inject_test.go` is missing), or Go module downloads fail so the oracle test cannot run.
