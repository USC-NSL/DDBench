# Solution: hashicorp/raft PR#609

- **Issue:** 42d34464b2d203e389e11ed6d43db698792c0604
- **Fix commit:** [`42d34464b2d203e389e11ed6d43db698792c0604`](https://github.com/hashicorp/raft/commit/42d34464b2d203e389e11ed6d43db698792c0604)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **PR:** https://github.com/hashicorp/raft/pull/609
- **Commit:** `42d34464b2d203e389e11ed6d43db698792c0604`

## Fix locus
- **Component:** Raft pre-vote protocol / follower election timer
- **File:** `raft.go`

## Root cause
In the `requestPreVote()` function in `raft.go`, when a follower grants a pre-vote request, it calls `r.setLastContact()` (line 1808). This updates the "last contact with leader" timestamp. However, a pre-vote request is not a heartbeat from a leader — it is a speculative request from a candidate that wants to check if it would win an election before actually starting one. Treating it as evidence of a healthy leader is incorrect.

When a node sends frequent pre-vote requests (e.g., a misconfigured node with a low election timeout, or a former leader that keeps cycling through pre-vote without winning), the followers' `lastContact` timestamp is continuously refreshed. This prevents the followers from timing out their election timer, which means they can never transition to candidate state and start a real election. The cluster becomes permanently stuck without a leader.

## Diagnosis chain
1. **Runtime evidence:** After a leader failure, the cluster does not elect a new leader despite all followers being healthy. Followers remain in follower state indefinitely. Concurrent pre-vote requests are visible in debug logs.
2. **Narrowing the component:** The issue is in the election timeout mechanism. Followers have a timer that fires when they haven't heard from a leader for `ElectionTimeout` duration. Something is resetting this timer even though the leader is gone. The `setLastContact()` call is the mechanism that resets this timer.
3. **Code-level reasoning:** In `raft.go`, the `requestPreVote()` function calls `r.setLastContact()` on line 1808 after setting `resp.Granted = true`. This line treats a granted pre-vote as equivalent to a leader heartbeat. Since pre-votes can arrive independently of actual leader activity, this creates a path where `lastContact` is refreshed without any real leader communication, preventing election timeout.

## Fix description
Remove the single line `r.setLastContact()` from the `requestPreVote()` function. Pre-vote responses should not update the last-contact timestamp because pre-votes are not leader heartbeats. The fix is a one-line deletion.

## How to apply
```bash
cd raft
git checkout 42d34464b2d203e389e11ed6d43db698792c0604
```

## How to verify
Run `reproduce.sh` which injects a test that creates a 3-node cluster, spams followers with pre-vote requests, blocks real leader heartbeats, and verifies that a new leader can still be elected. With the fix applied, followers time out normally and elect a new leader (PASS). Without the fix, followers never time out (FAIL).
