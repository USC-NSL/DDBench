# Symptom

When a JetStream consumer is created with a `FilterSubjects` configuration that matches all subjects in a stream, message delivery performance degrades by more than 20% compared to a consumer with no filter at all.

This is counterintuitive: a filter that matches everything should have the same performance as no filter. However, when a single subject is specified in the `FilterSubjects` field, the server activates the subject filtering code path, which adds per-message overhead even when every message would pass the filter anyway.

The performance difference is measurable:
- Consumer with no filter: ~X messages/sec
- Consumer with `FilterSubjects` matching all subjects: ~0.8X messages/sec (20%+ slower)

This affects any deployment where consumers use explicit subject filters that happen to match the entire stream, which is common in configurations that are programmatically generated.
