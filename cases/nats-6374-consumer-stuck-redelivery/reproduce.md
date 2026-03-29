# Reproduce: NATS Server #6374

Two bugs are demonstrated via Go test injection. Both tests are from the fix PR and exercise internal consumer state directly.

## Bug 1: Stuck consumer after leader step-down with inflight ack

### Setup

Create a JetStream server, publish 2000 messages to a stream, and create a pull consumer that fetches all 2000 messages without acknowledging them.

### Trigger

Simulate a leader step-down race condition:
1. Increment `o.awl` (simulating an inflight ack being pushed)
2. Call `o.setLeader(false)` -- this drains `o.ackMsgs` but does NOT reset `o.awl`
3. Call `o.setLeader(true)` -- consumer becomes leader again with stale `o.awl`
4. Try to fetch a message via `sub.Fetch(1)` with a 5-second timeout

### Expected result (bug present)

`sub.Fetch(1)` times out because `checkPending` sees `o.awl > 0` and short-circuits, preventing redelivery of the 2000 unacked messages.

### Test command

```bash
cd /path/to/nats-server
go test -v -run TestJetStreamConsumerSwitchLeaderDuringInflightAck -count=1 -timeout 120s ./server/
```

## Bug 2: Consumer slowdown when redelivering deleted message

### Setup

Create a JetStream server, publish 3 messages, create a pull consumer, and fetch all 3 without acknowledging. Then delete message 2 from the stream.

### Trigger

1. Clear the redelivery queue
2. Manually set `o.pending[2]` to point to the deleted message
3. Add sequence 2 to the redelivery queue
4. Call `o.getNextMsg()`

### Expected result (bug present)

`getNextMsg()` returns an error that is NOT `ErrStoreEOF` (it returns `errDeletedMsg` or `ErrStoreMsgNotFound` instead). Additionally, `o.pending` and `o.rdc` still contain the stale entry for sequence 2 -- they are never cleaned up.

### Test command

```bash
cd /path/to/nats-server
go test -v -run TestJetStreamConsumerMessageDeletedDuringRedelivery -count=1 -timeout 120s ./server/
```
