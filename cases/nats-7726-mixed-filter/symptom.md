# Symptom: NATS Server #7726

A JetStream consumer configured with multiple filter subjects that mix wildcard and literal patterns fails to deliver messages to the literal subjects.

For example, a consumer with filters `events.specific` (literal) and `events.*` (wildcard) will not deliver messages published to `events.specific`, even though both filter patterns should match it. The wildcard filter works for other subjects, but the literal filter is effectively broken by the presence of the wildcard.
