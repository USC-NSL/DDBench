# Solution: hashicorp/raft PR#581

## Fix
- **PR:** https://github.com/hashicorp/raft/pull/581
- **Commit:** `62eaa1c192d4c09c90caa5e227177eb9205a6267`

## Fix locus
- **Component:** Raft leadership transfer / write acceptance gate
- **Files:** `raft.go`, `raft_test.go`, `testing.go`

## Root cause
After the leader sends a `TimeoutNow` RPC to the transfer target, the leader continues accepting new `Apply()` requests. These writes append entries to the leader's log, advancing its last log index. When the transfer target starts its election, other nodes may have already received these newer entries from the leader. The target's log is now behind, so it cannot gather enough votes to win. This results in intermittent leadership transfer failures that correlate with write throughput.

## Diagnosis chain
1. **Runtime evidence:** Leadership transfers fail intermittently. The transfer target does not become leader; instead, a different node wins or the transfer times out. Failure rate increases with concurrent write load. Transfer succeeds reliably without concurrent writes.
2. **Narrowing the component:** The failure is in the election outcome, not the transfer initiation. The target receives the transfer signal and starts an election, but loses. This points to a log index discrepancy — the target's log falls behind during the transfer window.
3. **Code-level reasoning:** In `raft.go`, after sending the transfer signal, the leader's main loop continues processing apply requests. Each write advances the log index. The election target started at an earlier index, so by the time it requests votes, other followers have newer entries from the leader. The fix adds a write-blocking period after the transfer signal to prevent the leader from advancing its log during the transfer window.

## Fix description
The fix adds a flag and a timer that blocks new writes for up to `ElectionTimeout` after initiating the transfer. During this window, `Apply()` requests on the leader are held until either the transfer completes (new leader detected) or the timeout expires. This ensures the transfer target's log remains current relative to the rest of the cluster when it starts its election.

## How to apply
```bash
cd raft
git checkout 62eaa1c192d4c09c90caa5e227177eb9205a6267
go build ./...
```

## How to verify
Run `reproduce.sh` which exercises leadership transfers under concurrent write load 30 times. With the fix applied, transfers should succeed reliably (fewer than 5 failures out of 30).
