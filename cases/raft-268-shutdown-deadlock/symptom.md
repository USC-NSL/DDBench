# Symptom: hashicorp/raft #268

## Description

Calling `Raft.Shutdown()` can deadlock permanently if it races with a concurrent `takeSnapshot()` operation. The `Shutdown()` call never returns, causing the application to hang indefinitely during graceful shutdown.

## Observable behavior

- The application calls `raft.Shutdown()` (e.g., during graceful termination on SIGTERM).
- The call never returns — the goroutine is blocked forever.
- A goroutine dump (`kill -QUIT` or `runtime.Stack()`) shows:
  - The `runSnapshots` goroutine is blocked waiting on a channel (`configReq.Error()`) inside `takeSnapshot()`.
  - The main Raft goroutine has already exited its run loop, so it will never process the `configurationsCh` request that `takeSnapshot` sent.
  - `Shutdown()` is blocked waiting for `runSnapshots` to finish (via `waitShutdown`).
- This creates a circular dependency:
  1. `Shutdown()` waits for `runSnapshots` to complete.
  2. `runSnapshots` (in `takeSnapshot`) waits for a response on `configurationsCh`.
  3. The goroutine that would process `configurationsCh` has already exited.
- The deadlock is permanent — it will never resolve on its own.

## Impact

Any application using hashicorp/raft that attempts graceful shutdown can hang indefinitely if a snapshot happens to be in progress or about to start. This is a production issue for systems like Consul, Nomad, and Vault that use this library.
