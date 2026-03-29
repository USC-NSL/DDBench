# Symptom

A JetStream consumer becomes stuck and stops delivering messages after a consumer leader step-down. Two related bugs contribute to this behavior:

1. **Stuck consumer after leader step-down with inflight acks:** When a consumer leader steps down while there are inflight acks, the `o.awl` (ack wait length) counter is not reset even though `o.ackMsgs.drain()` clears the ack queue. On the next `checkPending` call, the non-zero `o.awl` causes the function to short-circuit, preventing any redelivery of unacknowledged messages. The consumer appears frozen -- no messages are delivered despite pending unacked messages.

2. **Consumer slowdown when redelivering deleted messages:** If a message is scheduled for redelivery but has been deleted from the stream in the meantime (e.g., via `js.DeleteMsg`), the consumer does not clean up the stale entry from `o.pending` and `o.rdc`. The consumer repeatedly tries to load the deleted message, fails, and returns the error without advancing. This causes significant slowdowns and can make the consumer appear stuck.

Both issues manifest as a consumer that stops delivering messages. The first is triggered by leader step-down timing, the second by message deletion during redelivery windows.
