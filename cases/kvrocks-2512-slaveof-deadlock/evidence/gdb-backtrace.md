# GDB Backtrace: kvrocks-2512-slaveof-deadlock

## How this was obtained

Attached `gdb` to the hung Kvrocks process and ran `thread apply all bt` to capture backtraces from all threads.

## Evidence

A `gdb` backtrace reveals the deadlock: one worker thread is blocked trying to acquire a shared read lock, while another worker thread holds that lock and is blocked waiting for the old replication thread to join. The old replication thread is blocked waiting for an exclusive write lock on the same mutex, which cannot be acquired because the first worker still holds the shared lock.
