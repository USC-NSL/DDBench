# Solution: Kvrocks #2512

## Fix
- **PR:** https://github.com/apache/kvrocks/pull/2516
- **Commit:** `ab41cbb69d081711437e25846c86c920cb5253e1`

## Fix locus
- **Component:** Server DB-restore preparation (`PrepareRestoreDB`)
- **Files:** `src/server/server.cc` (+6/-4)

## Root cause
The `SLAVEOF` command is tagged as `kCmdExclusive`, meaning the worker thread acquires `WorkExclusivityGuard` (a unique/write lock on `works_concurrency_rw_lock_`) before executing it. Inside `AddMaster`, if a previous replication thread exists, `ReplicationThread::Stop()` is called, which joins the replication thread via `t_.join()`.

Meanwhile, the replication thread, when performing a full sync (triggered by a PSYNC failure due to different replication IDs), calls `PrepareRestoreDB`. In the buggy code, `PrepareRestoreDB` attempts to acquire `WorkExclusivityGuard` itself and only then sets `is_loading_ = true`:

```cpp
// Buggy code in PrepareRestoreDB:
{
    auto exclusivity = WorkExclusivityGuard();  // blocks waiting for exclusive lock
    is_loading_ = true;
}
```

The deadlock occurs as follows:

1. **T0:** Client A sends `SLAVEOF master1`. The worker thread acquires `WorkExclusivityGuard` (exclusive lock), calls `AddMaster`, which starts a replication thread. The command completes and the exclusive lock is released.

2. **T1:** The replication thread fails PSYNC (different replication ID) and enters `PrepareRestoreDB`. It blocks on `WorkExclusivityGuard()`, waiting for the exclusive lock on `works_concurrency_rw_lock_`.

3. **T2:** Client B sends `SLAVEOF master2`. A worker thread acquires `WorkExclusivityGuard` (exclusive lock) because SLAVEOF is `kCmdExclusive`. It calls `AddMaster`, which calls `replication_thread_->Stop()`. `Stop()` calls `t_.join()` to wait for the old replication thread to finish.

4. **Deadlock:** The worker thread (T2) holds the exclusive lock and waits for the replication thread (T1) to join. The replication thread (T1) waits for the exclusive lock held by the worker thread (T2). Neither can proceed.

## Diagnosis chain
1. **Runtime observation:** After two rapid `SLAVEOF` commands to different masters, the Kvrocks slave becomes completely unresponsive. No error logs, no crash -- just a permanent hang. Only a process restart recovers it.
2. **Pattern recognition:** The hang occurs specifically when switching masters rapidly. The `SLAVEOF` command requires an exclusive lock (`kCmdExclusive`), and `PrepareRestoreDB` also acquires the same exclusive lock. Two threads contending for the same exclusive lock with a join dependency is a classic deadlock pattern.
3. **Code reasoning:** Tracing the execution: the worker thread holds `WorkExclusivityGuard` while calling `AddMaster` -> `ReplicationThread::Stop()` -> `t_.join()`. The replication thread is inside `PrepareRestoreDB`, blocked on `WorkExclusivityGuard()`. The join waits for the thread that waits for the lock that the joiner holds -- a circular dependency.
4. **Root cause confirmed:** The root cause is that `is_loading_ = true` is set inside the exclusive lock scope in `PrepareRestoreDB`. Since `is_loading_` is an `std::atomic<bool>`, it can safely be set without holding the lock. The exclusive lock is only needed to ensure no worker is mid-command when loading begins, but the flag itself can be set beforehand to reject new commands early.

## Fix description
The fix moves `is_loading_ = true` out of the `WorkExclusivityGuard` scope and sets it *before* acquiring the exclusive lock:

```cpp
// Fixed code in PrepareRestoreDB:
is_loading_ = true;  // Set flag first to stop new commands

{ auto exclusivity = WorkExclusivityGuard(); }  // Then drain in-flight commands
```

By setting `is_loading_ = true` first, worker threads that have already acquired the shared concurrency lock will check this flag and return an error ("loading in-progress") instead of executing DB-accessing commands. Workers that have not yet acquired the lock will see `is_loading_` is true after acquiring their shared lock and also bail out. The exclusive lock acquisition in `PrepareRestoreDB` then only serves as a barrier to ensure all in-flight commands have completed -- it is acquired and immediately released.

This breaks the deadlock because:
- When the second `SLAVEOF` command's worker thread holds the exclusive lock and calls `replication_thread_->Stop()`, the old replication thread in `PrepareRestoreDB` will find the exclusive lock acquisition returns quickly (since the worker that triggered `Stop` holds the exclusive lock, but the replication thread no longer needs the exclusive lock to set `is_loading_`). Actually, more precisely: with `is_loading_` already set to true, workers will refuse new commands, and the exclusive lock in `PrepareRestoreDB` no longer creates the circular wait because the replication thread can be stopped (via `stop_flag_`) before it reaches the lock acquisition, or the lock scope is minimal enough to avoid the deadlock window.

The key insight is that `is_loading_` is atomic and can safely signal workers to stop without holding the exclusive lock, eliminating the circular dependency between the replication thread's lock acquisition and the worker thread's `Stop()` + `join()` call.

## How to apply
```bash
git checkout ab41cbb69d081711437e25846c86c920cb5253e1
git submodule update --init --recursive
mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Debug -DDISABLE_JEMALLOC=ON && make -j$(nproc)
```

## How to verify
Run `reproduce.sh` -- should print `PASS: Bug is fixed`. The test instruments `PrepareRestoreDB` with a 2-second sleep to widen the race window, then sends two rapid `SLAVEOF` commands. With the fix, the second command completes without deadlock and the slave responds to `PING`.
