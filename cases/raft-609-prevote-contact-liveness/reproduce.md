# Reproduce: hashicorp/raft #609

## Prerequisites
- Run inside `./bench.sh shell raft-609-prevote-contact-liveness`, from `/workspace/src` (hashicorp/raft at the buggy commit; the Go toolchain is in the image).
- The test file is the case's `inject_test.go`, mounted at `/bench/inject_test.go`.

## Step 1: Inject the test

Copy the test file into the raft source tree:
```bash
cp /bench/inject_test.go /workspace/src/prevote_contact_bug_test.go
```

The test (`TestPreVoteLeaderSpamBlocksElection`) does the following:

1. Creates a 3-node raft cluster with pre-vote enabled and tight timeouts (50ms heartbeat/election)
2. Waits for a stable leader and consistent log state
3. Starts a goroutine that continuously sends pre-vote requests to all followers at 25ms intervals
4. After 1 second of pre-vote spam, installs custom heartbeat handlers on all followers that reject heartbeats from the current leader (simulating leader failure)
5. Waits 1 second, then checks if any follower has become the new leader

## Step 2: Run the test

The test uses `NetworkTransport` (TCP) and requires the `INTEG_TESTS` environment variable:

```bash
INTEG_TESTS=1 go test -v -run "^TestPreVoteLeaderSpamBlocksElection$" -count=1 -timeout 90s .
```

## Expected result (bug present)

The test FAILs because:
- Pre-vote requests refresh `lastContact` via `setLastContact()` in `requestPreVote()`
- Followers believe they are still in contact with a leader (even though they are not)
- Followers never time out their election timer
- No follower transitions to candidate state
- No new leader is elected
- `WaitForAny(Leader, followers)` returns an error after 200ms

```
--- FAIL: TestPreVoteLeaderSpamBlocksElection (X.XXs)
    integ_test.go:XXX: err: failed to find node in Leader state
FAIL
```

## Expected result (bug fixed)

The test PASSes because:
- Pre-vote requests no longer call `setLastContact()`
- After real heartbeats are blocked, followers' `lastContact` timestamp is not refreshed
- Followers time out their election timer after 50ms
- One follower transitions to candidate, wins the election, becomes leader
- `WaitForAny(Leader, followers)` finds the new leader

```
--- PASS: TestPreVoteLeaderSpamBlocksElection (X.XXs)
PASS
```

## Oracle verdict

`./bench.sh reproduce raft-609-prevote-contact-liveness` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): at least one of 3 runs of the injected integration test `TestDDBenchOraclePreVoteSpamElection` (`INTEG_TESTS=1`, TCP transport) fails: in a 3-node cluster whose followers keep receiving pre-vote requests from the leader every 25 ms and then stop accepting its heartbeats, no follower becomes leader; a run that otherwise fails or exceeds its 120 s timeout also counts. A worktree that does not build, or a package or injected test that does not compile (or a skipped test), is also FAIL.
- **PASS** (exit 0): all 3 runs pass: in each, a follower is elected leader despite the pre-vote requests.
- **ERROR** (exit 2): `REBUILD.sh`, `raft.go` or `inject_test.go` is missing, or the test did not run because a Go module download failed (network).
