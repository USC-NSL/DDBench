# Solution: hashicorp/raft #517

## Fix
- **Issue:** https://github.com/hashicorp/raft/issues/517
- **Fix PR:** https://github.com/hashicorp/raft/pull/570
- **Fix commit:** `49bd61b66666fa76cb23fa81897e350f6e9b75de`

## Fix locus
- **Component:** Raft state machine / leadership transfer synchronization
- **Files:** `api.go`, `raft.go`

## Diagnosis chain
1. **Runtime evidence:** The Go race detector reports `WARNING: DATA RACE` with stack traces pointing to a write in the candidate state goroutine and a read in the AppendEntries handler goroutine, both accessing the same memory address.
2. **Narrowing the component:** The race occurs during leadership transfer — specifically at the intersection of the candidate state machine (which writes a flag on exit) and the heartbeat handler (which reads the same flag). This narrows the fault to the leadership transfer coordination logic.
3. **Code-level reasoning:** The `candidateFromLeadershipTransfer` field is a plain `bool` accessed from two goroutines without synchronization. The candidate goroutine writes it on exit, while the RPC handler reads it during heartbeat processing. The fix converts it to use atomic operations.

## Root cause

The `candidateFromLeadershipTransfer` field on the Raft struct is a plain `bool` that is accessed without synchronization from multiple goroutines:

1. **`runCandidate()` goroutine** — Writes `candidateFromLeadershipTransfer = false` when exiting the candidate state (e.g., after the election completes or times out).

2. **`appendEntries()` handler** — Reads `candidateFromLeadershipTransfer` while processing incoming heartbeat (AppendEntries RPC) requests during leadership transfer. This runs on a different goroutine handling the RPC.

When a leadership transfer is in progress, `runCandidate()` sets the flag to `true` on entry and resets it to `false` on exit. Meanwhile, `appendEntries()` checks this flag to determine how to respond to heartbeats. These concurrent read/write operations on a plain `bool` without any locking or atomic operations constitute a data race.

## Fix description

The fix converts the `candidateFromLeadershipTransfer` field from a plain `bool` to use atomic operations for safe concurrent access:

1. **`api.go`** (+1, -1) — Changes the field type from `bool` to an atomic type (e.g., `atomic.Bool` or `int32` with atomic operations).

2. **`raft.go`** (+4, -4) — Replaces all direct reads and writes of `candidateFromLeadershipTransfer` with atomic load and store operations:
   - In `runCandidate()`: Uses atomic store when setting the flag to `true` on entry and `false` on exit.
   - In `appendEntries()`: Uses atomic load when reading the flag during heartbeat processing.

This eliminates the data race by ensuring all accesses to the shared field are properly synchronized through atomic operations.

## Files changed

- **`api.go`** — Changed `candidateFromLeadershipTransfer` field type to use atomic operations.
- **`raft.go`** — Replaced direct bool read/write with atomic load/store in `runCandidate()` and `appendEntries()`.

## How to apply the fix
```bash
cd raft
git checkout 49bd61b66666fa76cb23fa81897e350f6e9b75de
go build ./...
```
