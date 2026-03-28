# Symptom

A data race is detected during leadership transfer operations in a multi-node raft cluster.

## Observable behavior
- Running a multi-node raft cluster with the Go race detector enabled (`-race`).
- Triggering leadership transfer operations repeatedly.
- The Go race detector reports `WARNING: DATA RACE` between a goroutine performing candidate operations and a goroutine handling append entries (heartbeat) requests.
- The race involves concurrent unsynchronized access to shared state between the two code paths.
- The race is timing-dependent and may require multiple iterations to trigger.
