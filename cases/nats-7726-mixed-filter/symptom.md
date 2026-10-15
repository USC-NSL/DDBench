# Symptom

A JetStream pull consumer whose filter subjects mix wildcard patterns with a literal subject does not deliver messages published to the literal subject.

Setup (single server, file or memory storage):

- A stream with subjects `events.>`.
- A pull consumer (`DeliverAll`, explicit ack) with these filter subjects:
  - `events.*.datastore.batch.access.modified`
  - `events.*.processor.complete.batch.inserted`
  - `events.main.datastore.result.created`
- The stream already holds messages that match none of the filters but share the literal filter's prefix: `events.main.datastore.record.created`, `events.main.datastore.group.created`, `events.main.datastore.batch.created`, and four messages on `events.main.datastore.items.created`.

A message is then published to `events.main.datastore.result.created`. Stream info shows that it was stored: the stream now holds 8 messages. A fetch from the consumer, for example `nats consumer next <stream> <consumer> --timeout 3s`, times out with no message.

Expected: the consumer delivers the message on `events.main.datastore.result.created`. That subject is one of its filter subjects, so the consumer should deliver it whatever other filters are configured and whatever other messages are in the stream.
