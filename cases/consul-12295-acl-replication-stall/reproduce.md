# Reproduce: Consul #12295

## Prerequisites

- Git, Go 1.17+
- The buggy commit checked out (done by `setup.sh`)

## Step 1: Set up the codebase

```bash
./setup.sh
```

This clones `https://github.com/hashicorp/consul.git` and checks out the buggy commit (`24245edf~1`).

## Step 2: Run the reproduction test

```bash
./reproduce.sh
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
FAIL: Bug is present — IsRunning() returns true after parent context cancelled,
      ACL replication will not restart after leadership re-election
```

## Expected result (bug fixed)

```
--- PASS: TestManager_IsRunningAfterParentContextCancel (...)
PASS
PASS: Bug is fixed — IsRunning() correctly returns false after parent context cancelled
```
