# Symptom

Messages are silently lost in a JetStream stream configured with WorkQueue retention policy and R3 replication when consumers reach their max-deliver limit.

Specifically: when a consumer is configured with a `max-deliver` limit and some messages are not acknowledged (reaching the max delivery count), those messages should remain in the stream (since they could not be delivered to any consumer). However, with WorkQueue retention on R3 streams, the messages are incorrectly removed from the stream.

For example, publishing 200 messages and not acknowledging every 10th message should leave 20 unacknowledged messages in the stream, but only 9 (or fewer) remain.
