# Symptom

A JetStream consumer becomes stuck and stops delivering messages. Two scenarios trigger this behavior:

1. **Stuck consumer after leader step-down with inflight acks:** When a consumer leader steps down while there are inflight acknowledgments, the consumer stops delivering messages after it becomes leader again. No messages are delivered despite pending unacknowledged messages existing.

2. **Consumer slowdown when redelivering deleted messages:** If a message is scheduled for redelivery but has been deleted from the stream in the meantime (e.g., via the message delete API), the consumer becomes severely slow or appears stuck. It fails to advance past the deleted message during redelivery attempts.

Both issues manifest as a consumer that stops delivering messages. The first is triggered by leader step-down timing, the second by message deletion during redelivery windows.
