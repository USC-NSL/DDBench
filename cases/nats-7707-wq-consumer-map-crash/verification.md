# Verification: NATS #7707

## Automated test

```bash
./reproduce.sh
```

The script injects a Go test (`TestWQConsumerPartitionRace`) into the nats-server source tree and runs it with the Go race detector. It exercises the race condition by concurrently creating, updating, and deleting consumers on a WorkQueue stream while publishing messages.

## Pass/fail criteria

- **FAIL (bug present):** The Go race detector reports a `DATA RACE` involving the consumer map, or the test process crashes with `fatal error: concurrent map iteration and map write`. Typically detected within 1-3 iterations.
- **PASS (bug fixed):** No race condition or crash is detected across 5 iterations of the test. All consumer create/update/delete operations complete without triggering a fatal error.
