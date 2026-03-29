# Symptom

When a Kvrocks instance receives rapid successive `SLAVEOF` commands pointing to different masters, the server deadlocks and becomes completely unresponsive. No error messages appear in the logs; the process simply hangs.

## Observable behavior
- After issuing two or more `SLAVEOF` commands in quick succession (switching between different masters), the Kvrocks instance stops responding to all commands, including `PING`.
- The server process remains running but all worker threads are blocked. No crash, no error log, no timeout message.
- A `gdb` backtrace reveals the deadlock: one worker thread is blocked trying to acquire `WorkConcurrencyGuard` (a shared read lock on `works_concurrency_rw_lock_`), while another worker thread holds that lock and is blocked in `ReplicationThread::Stop()` waiting for the old replication thread to join. The old replication thread is blocked waiting for `WorkExclusivityGuard` (an exclusive write lock on the same `works_concurrency_rw_lock_`), which cannot be acquired because the first worker still holds the shared lock.
- The deadlock is a classic lock-ordering violation: Thread A holds shared lock and waits for Thread B to finish; Thread B waits for exclusive lock held by Thread A.
- Restarting the Kvrocks process is the only recovery. The deadlock is permanent once triggered.
- The issue is reliably triggered by rapidly switching masters (e.g., `SLAVEOF host1 port1` immediately followed by `SLAVEOF host2 port2`).
