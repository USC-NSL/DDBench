# Symptom: Dragonfly #6654

When using the memcached protocol with meta get commands, retrieving a large value causes a crash. The reply builder attempts to buffer the response but the computed `expected_buffer_cap` (e.g., 8242 bytes) exceeds the `kMaxBufferSize` constant (8192 bytes), triggering a fatal assertion.

This only occurs with the memcached protocol, not with the Redis protocol, and only when the value is large enough to push the meta get reply header + value size beyond the buffer limit.
