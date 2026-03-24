# Symptom

When `DB::Close()` is called while some write operations are stalled (blocked by the write rate limiter or by L0 stop-writes conditions), the `Close()` call hangs indefinitely.

The stalled writer threads are waiting on a condition variable to be signaled that they can proceed. However, during shutdown, no one wakes them up — the shutdown sequence does not release the write stall condition. The result is a deadlock:

- The `Close()` call waits for all background work to finish
- Stalled writer threads are blocked, waiting for the stall condition to clear
- The stall condition will never clear because `Close()` is shutting down compaction/flush threads
- The process hangs forever

This affects any application that:
1. Uses a write rate limiter or has aggressive L0 stop-writes settings
2. Performs writes fast enough to trigger write stalling
3. Calls `DB::Close()` during or shortly after the stall

The hang is deterministic once the write stall + shutdown race is reached.
