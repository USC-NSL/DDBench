# Reproduce: hashicorp/raft #609

## Prerequisites
- Go 1.21+ installed
- hashicorp/raft checked out at the buggy version (see setup.md)

## Step 1: Inject the test

Copy the test file into the raft source tree:
```bash
cp inject_test.go /path/to/raft/prevote_contact_bug_test.go
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
