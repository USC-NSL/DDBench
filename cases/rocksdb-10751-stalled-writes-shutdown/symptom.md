# Symptom

When `DB::Close()` is called while write operations are stalled (due to write rate limiting or L0 stop-writes conditions), the `Close()` call hangs indefinitely.

## Observable behavior
- The process hangs forever on `DB::Close()`.
- The hang is deterministic once writes are stalled at the time of shutdown.
- This affects any application that uses a write rate limiter, performs writes fast enough to trigger stalling, and calls `DB::Close()` during the stall.
