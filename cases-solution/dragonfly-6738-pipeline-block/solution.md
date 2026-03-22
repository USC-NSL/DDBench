# Solution: Dragonfly #6738

## Fix
- **PR:** https://github.com/dragonflydb/dragonfly/pull/6743
- **Commit:** `c4849b4d008d1dd6fd950f251cdb9a9a2e264e00`

## Root cause

When a blocking command (`BRPOPLPUSH`, `BLMOVE`, etc.) is encountered in a pipeline or as part of Lua script execution, the replies are not flushed before the command starts blocking. Additionally, the destination shard is not properly notified when data becomes available.

Specifically, when `RPUSH` runs inside `EVAL`, the write notification that should wake blocked consumers on the destination shard is not sent because the reply flushing mechanism that triggers shard wake-up is skipped during pipeline/script execution.

## Fix description

The fix ensures that replies are flushed when a blocking command is encountered in a pipeline. This triggers the proper wake-up notification to the shard where a consumer is blocked.

Key changes:
- When processing a pipeline and encountering a blocking command, flush all pending replies before entering the blocking state.
- Ensure the shard notification for blocked consumers is sent regardless of whether the RPUSH originated from a Lua script or a direct command.

## How to apply
```bash
git checkout c4849b4d008d1dd6fd950f251cdb9a9a2e264e00
git submodule update --init --recursive
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```

## How to verify
Start BRPOPLPUSH consumer, push via EVAL, verify immediate wake-up (see verification.md).
