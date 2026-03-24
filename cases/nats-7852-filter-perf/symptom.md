# Symptom

When a JetStream consumer is created with a `FilterSubjects` configuration that matches all subjects in a stream, message delivery performance degrades by more than 20% compared to a consumer with no filter at all.

## Observable behavior
- A filter that matches everything should have the same performance as no filter, but it is significantly slower.
- The performance difference is consistent and measurable (~20%+ degradation).
- This affects deployments where consumers use explicit subject filters that happen to match the entire stream.
