# Solution: ClickHouse #43816

## Fix
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/43816

## Root cause

A deadlock occurs between two components:

1. **ReplicatedMergeTreeQueue** holds its queue mutex and calls into `MergeTreeBackgroundExecutor` to wait for a merge task to complete (via `setActualPartName`).
2. **MergeTreeBackgroundExecutor** holds its own mutex and tries to call back into `ReplicatedMergeTreeQueue` to update status.

This creates a classic lock-ordering deadlock. Merges start (slots are allocated in the background pool) but cannot complete because the thread holding the queue lock is waiting for the executor, and the executor is waiting for the queue lock.

Thread stacks show:
- Thread A: `ReplicatedMergeTreeQueue::pullEntry` -> lock queue -> `setActualPartName` -> wait on executor
- Thread B: `MergeTreeBackgroundExecutor::threadFunction` -> lock executor -> callback into queue -> wait on queue lock

## Fix description

This was fixed across multiple PRs in later ClickHouse versions (23.x+) by refactoring the background pool and queue interaction to avoid nested lock acquisition:

1. The background pool executor was redesigned to not hold its internal lock when calling back into the queue.
2. `setActualPartName` was refactored to use asynchronous notification instead of synchronous waiting.
3. Lock ordering was enforced to prevent future deadlocks.

## How to apply
Upgrade to ClickHouse 23.3+ which contains the accumulated fixes to the background merge pool. The specific fix spans multiple commits and cannot be cleanly cherry-picked to 22.10.

## How to verify
Run sustained write load (see reproduce.md) for 30+ minutes. Verify that:
- No merges are stuck at 0 progress for >10 minutes
- Part count stabilizes rather than growing unbounded
- No threads are stuck in `pthread_cond_wait` inside `setActualPartName`
