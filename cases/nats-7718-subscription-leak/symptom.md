# Symptom

When using JetStream with overlapping stream imports (e.g., importing both `events.>` and `events.critical.>` from the same account), rapidly creating and destroying OrderedConsumers causes a subscription leak.

Observable symptoms:
1. The subscription count reported by `nats server info` or the monitoring endpoint (`/varz`) grows continuously and never decreases.
2. Memory usage of the NATS server process increases over time.
3. Eventually, performance degrades as the server manages an ever-growing number of leaked subscriptions.
4. The leak rate is proportional to the rate of OrderedConsumer creation/destruction.

The subscriptions are "orphaned" -- they remain registered in the server but have no associated active consumer.
