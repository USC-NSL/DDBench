# Symptom

On an interest-based, replicated (R5) stream, a pull consumer with several filter subjects stops delivering messages after its filter subjects are edited and its leader is then stepped down (for example with `nats consumer cluster step-down`).

Before the edit, and after the edit but before the step-down, the consumer works correctly. After the step-down, messages published to a subject that is still one of the consumer's filter subjects are never delivered: `nats consumer next` times out with `nats: error: no message received: nats: timeout`. The consumer's `Unprocessed Messages` stays at 0, and the stream stops gaining messages, so the matching messages are lost.
