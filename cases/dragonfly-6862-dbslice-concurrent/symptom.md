# Symptom

## Description

When running Dragonfly in cluster mode with multiple proactor threads, concurrent write operations combined with cluster management operations (such as slot migration or cluster configuration changes) cause the process to crash. The crash occurs in `db_slice.cc` at line 550, indicating a data structure integrity issue due to concurrent access.

## Observable behavior

- Dragonfly crashes with an assertion failure or segfault in `db_slice.cc:550`.
- The crash occurs under concurrent write load when cluster management operations are happening simultaneously.
- The crash trace shows access to `DbSlice` internals from multiple threads.
- The crash is non-deterministic — it depends on exact timing of concurrent operations.
- Running with a single proactor thread (`--proactor_threads 1`) may not trigger the bug.
- Running without cluster mode (`--cluster_mode=no`) does not trigger the bug.
- Higher write throughput and more proactor threads increase the probability of the crash.

## Impact

Production Dragonfly clusters can crash during routine cluster management operations (slot migration, rebalancing, configuration updates) if there is concurrent write traffic, which is the normal operating condition.
