# Solution: RabbitMQ #12635

## Fix
- **PR:** https://github.com/rabbitmq/rabbitmq-server/pull/12636
- **Commit:** `94e677987f1452980a0692e431a6c813fb244833` (merged as `ef2c8dfbdafb4e47beab0d3cb9d64b0a2f56fbaf`)

## Root cause

The bug is in `deps/rabbit/src/rabbit_fifo.erl`, in two log effect callback functions:

1. **`delivery_effect/3` (line ~2055):** When a quorum queue member needs to deliver messages to a consumer, it creates a `{log, RaftIdxs, Fun}` effect that reads log entries at the given Raft indexes and passes them to a callback. The callback uses `lists:zipwith` to pair each log command with the corresponding message metadata. After a snapshot installation, the log may have been truncated and return fewer entries than requested. Since `lists:zipwith` requires both lists to have the same length, it crashes with a `badarg` error when the lists differ.

2. **`reply_log_effect/5` (line ~2076):** Similar issue. The callback pattern-matches `fun ([Cmd]) -> ...` expecting exactly one command. If the log returns an empty list (stale read), the pattern match fails.

The sequence leading to the crash:
- A follower is stopped while messages are published, consumed, and checkpointed on the leader
- A consumer subscribes to the follower's node while it is stopped, creating consumer references in the queue state
- The follower restarts, installs the snapshot from the leader
- The snapshot includes delivery effects referencing log entries that were already truncated by the checkpoint
- The `delivery_effect/3` callback receives an empty or short command list from the log, crashes in `lists:zipwith`

## Fix description

Two changes in `deps/rabbit/src/rabbit_fifo.erl` (24 lines added, 8 removed):

1. **`delivery_effect/3`:** The log callback function now tracks the expected number of entries (`Num`) and adds a guard clause `when length(Commands) < Num`. When fewer commands are returned than requested (indicating a stale read after snapshot installation), the function logs an info message and returns an empty effect list `[]` instead of attempting the `lists:zipwith`.

2. **`reply_log_effect/5`:** Adds a clause `fun ([]) -> []` before the existing `fun ([Cmd]) -> ...` clause, so an empty log result returns an empty effect list instead of crashing on the pattern match.

Both changes make the log effect callbacks defensive against stale reads, treating them as no-ops rather than crashing.

## How to apply
```bash
git cherry-pick 94e677987f1452980a0692e431a6c813fb244833
make -j$(nproc)
```
