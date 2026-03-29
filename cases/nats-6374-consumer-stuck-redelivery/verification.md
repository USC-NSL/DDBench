# Verification: NATS Server #6374

Two Go tests from the fix PR are injected into `server/jetstream_consumer_test.go` and executed against the buggy codebase.

## Test 1: Leader step-down with inflight ack

```bash
go test -v -run TestJetStreamConsumerSwitchLeaderDuringInflightAck -count=1 -timeout 120s ./server/
```

- **FAIL (bug present):** `sub.Fetch(1)` times out after 5 seconds. The consumer is stuck because `o.awl` was not reset during `setLeader(false)`, causing `checkPending` to short-circuit.
- **PASS (bug fixed):** `sub.Fetch(1)` returns a redelivered message within the timeout.

## Test 2: Deleted message during redelivery

```bash
go test -v -run TestJetStreamConsumerMessageDeletedDuringRedelivery -count=1 -timeout 120s ./server/
```

- **FAIL (bug present):** `getNextMsg()` returns `errDeletedMsg` or `ErrStoreMsgNotFound` instead of `ErrStoreEOF`, and `o.pending`/`o.rdc` still contain the stale entry for the deleted message.
- **PASS (bug fixed):** `getNextMsg()` returns `ErrStoreEOF` after cleaning up the deleted message from `o.pending` and `o.rdc`.

## Combined verification

The `reproduce.sh` script runs both tests and reports:
- **FAIL:** if either test fails (bug is present)
- **PASS:** if both tests pass (bug is fixed)
