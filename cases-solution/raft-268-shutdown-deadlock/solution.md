# Solution: hashicorp/raft #268

- **Issue:** https://github.com/hashicorp/raft/issues/268
- **Fix commit:** [`2e997410f28efe8106fc606d21cb655be1b05dee`](https://github.com/hashicorp/raft/commit/2e997410f28efe8106fc606d21cb655be1b05dee)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix
- **Fix PR:** https://github.com/hashicorp/raft/pull/390

## Root cause

The deadlock involves three goroutines and two channels:

1. **`runSnapshots` goroutine** — Runs `takeSnapshot()`, which needs the current configuration. It sends a request on `configurationsCh` and blocks waiting for the response on `configReq.Error()`.

2. **Main Raft `run()` goroutine** — Processes requests from `configurationsCh` (among other channels) in a select loop. When `Shutdown()` is called, this goroutine exits the select loop and returns.

3. **Caller goroutine** — Calls `Shutdown()`, which signals the run loop to exit, then calls `waitShutdown()` which waits for `runSnapshots` to finish.

The deadlock sequence:
1. `takeSnapshot()` sends on `configurationsCh` and blocks on the response.
2. The main run loop exits before processing the `configurationsCh` request (because shutdown was signaled).
3. `Shutdown()` calls `waitShutdown()`, waiting for `runSnapshots` to complete.
4. `runSnapshots` is stuck waiting for a response that will never come.

Result: `Shutdown()` waits for `runSnapshots`, which waits for `run()`, which has already exited.

## Fix description

The fix makes futures (like the `configReq` sent on `configurationsCh`) react to the shutdown signal. Instead of blocking indefinitely on `configReq.Error()`, the code checks both the response channel and the shutdown channel. If shutdown is signaled, the pending future is cancelled with an error, allowing `takeSnapshot()` to return and `runSnapshots` to complete.

Specifically:
- Futures now include a reference to the shutdown channel.
- When waiting for a future's result, the code uses a `select` that also listens for the shutdown signal.
- If shutdown is received while waiting, the future returns `ErrRaftShutdown`.

## Files changed

- **`raft.go`** — Modified future handling to include shutdown awareness. The `configurationsFuture` and similar futures now check for shutdown when waiting for their response.
- **`api.go`** (or future types file) — Updated future types to accept and check a shutdown channel alongside their response channel.

## How to apply the fix
```bash
cd raft
git checkout 2e997410f28efe8106fc606d21cb655be1b05dee
go build ./...
```
