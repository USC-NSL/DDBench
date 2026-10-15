# Solution: Dragonfly #6738

- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6738
- **Fix commit:** [`c4849b4d008d1dd6fd950f251cdb9a9a2e264e00`](https://github.com/dragonflydb/dragonfly/commit/c4849b4d008d1dd6fd950f251cdb9a9a2e264e00)
- **Gold patch:** [`gold.patch`](gold.patch) (source-only; `./bench.sh validate-oracle` applies it)

## Fix

- **PR:** https://github.com/dragonflydb/dragonfly/pull/6743 ("fix(server): flush replies on encountering blocking command in pipeline")
- **Commit:** `c4849b4d008d1dd6fd950f251cdb9a9a2e264e00`
- **Issue history:** the issue was opened as "BRPOPLPUSH not woken by LPUSH/RPUSH inside Lua script (EVALSHA)" (Bull queue under n8n) and retitled "Blocking commands in pipeline do not flush their replies" after diagnosis. A maintainer's reproducer pipelines several `BRPOPLPUSH` commands on one connection and pushes from another client; no Lua is needed. The upstream regression test (`test_blocking_command_pipeline_flush`, not part of gold.patch) pipelines `SET`, `PING` and three `BLPOP`, checks that the `SET`/`PING` replies arrive promptly, and checks that the first `BLPOP` is answered promptly after a delayed `LPUSH`. The case follows the issue as diagnosed and fixed. The original "Lua push does not wake the consumer" reading of the report is not a separate bug.

## Fix locus

- **Component:** connection reply batching for pipelined (asynchronously dispatched) commands (`facade::Connection`, `Service::DispatchCommand`)
- **Files:**
  - `src/server/main_service.cc` (+1): in `Service::DispatchCommand`, flush pending replies when a blocking command is dispatched asynchronously
  - `src/facade/dragonfly_connection.cc` (+5), `src/facade/dragonfly_connection.h` (+2): new public `Connection::FlushReplies()` that flushes the connection's reply builder

## Root cause

To batch replies, a connection with more than one pending command puts its reply builder in batch mode (`SetBatchMode(true)`). It dispatches the queued commands as one batch (`DispatchManyCommands`, with `cc_->async_dispatch` set), and flushes only after the whole batch has been dispatched and no new commands have arrived. A blocking command (`BLPOP`, `BRPOPLPUSH`, `BLMOVE`, ...) in the middle of a pipeline suspends the dispatch of that connection until it is woken or times out. Every reply buffered before it stays in the reply builder for that whole time. `DispatchCommand` already recognized this case (`dfly_cntx->async_dispatch && cid->IsBlocking()`), but it only incremented the `blocking_commands_in_pipelines` counter.

With several pipelined `BRPOPLPUSH` (Bull's worker pattern), the first pop is woken by the producer's push and its reply is buffered. The next pop then blocks until its timeout, so the client sees the job only after the remaining pops time out. That is why `MONITOR` showed the push executing while workers kept re-issuing `BRPOPLPUSH` every 5 s.

## Diagnosis chain

1. **Runtime evidence:** `MONITOR` shows the Lua `RPUSH` executing and the list growing, so the push happens and the element is popped (the list drains). The client still receives it late, in multiples of the blocking timeout. Replaying the worker's traffic shows that the delay requires several commands pipelined on one connection; the same commands sent one at a time are answered at once. A pipeline `SET`, `PING`, `BLPOP` on an empty list delays even the `SET`/`PING` replies until the `BLPOP` times out. The Lua script is not involved: a plain `RPUSH` from another client gives the same delay.
2. **Narrowing the component:** the commands execute promptly (`MONITOR`, list contents), and only the delivery of their replies is delayed. That points at the connection's reply path for pipelined commands rather than the list or blocking-wakeup code.
3. **Code-level reasoning:** in `facade::Connection`, pipelined commands are queued and dispatched as a batch through `Service::DispatchManyCommands` with `async_dispatch` set. The reply builder runs in batch mode, and `reply_builder_->Flush()` is called only after the batch returns. In `Service::DispatchCommand`, the branch `if (dfly_cntx->async_dispatch && cid->IsBlocking())` only counts the event. Nothing flushes the builder before the command blocks, so every earlier reply waits for the blocking command.

## Fix description

`Connection` gets a public `FlushReplies()` that calls `reply_builder_->Flush()`. `Service::DispatchCommand` calls `cmd_cntx->conn()->FlushReplies()` in the existing `async_dispatch && IsBlocking()` branch, so all replies buffered so far are sent before a pipelined blocking command can block. The reply of a woken blocking command is buffered and is flushed when the next pipelined blocking command is dispatched, or when the queue drains. Any fix that sends previously produced replies before a pipelined command blocks passes the oracle, for example flushing in the blocking command's wait path.

## How to verify

```bash
./bench.sh validate-oracle dragonfly-6738-pipeline-block --runs 3   # buggy worktree FAILs, gold.patch PASSes -> SOUND
./bench.sh eval dragonfly-6738-pipeline-block --patch cases-solution/dragonfly-6738-pipeline-block/gold.patch
```
