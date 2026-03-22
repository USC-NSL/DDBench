# Symptom: Kvrocks #3339

Under concurrent load, `XREADGROUP GROUP ... BLOCK` sends a double response to the client. The client receives two replies for a single `XREADGROUP` command:

1. First, an empty array response (the initial empty result when no data is available).
2. Then, the actual stream entry when new data arrives via `XADD`.

This violates the Redis protocol, which expects exactly one response per command. Most Redis client libraries interpret the second response as belonging to the next pipelined command, causing protocol desynchronization and cascading errors.

The issue manifests under concurrent load when multiple clients are doing `XREADGROUP BLOCK` on the same stream while other clients are concurrently calling `XADD`.
