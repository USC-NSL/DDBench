# Symptom

After editing a consumer's filter subjects and then triggering a leader step-down on an interest-based replicated stream (R5), the consumer stops matching messages. Publishing messages that should match the consumer's filter subjects results in a timeout — no messages are delivered.

The stream itself continues to accept publishes, but the consumer appears to have lost track of its filter subjects. This only happens after a leader step-down following a filter edit; without the step-down, the consumer works correctly.
