# Symptom

In a Ra Raft cluster (used as the consensus layer beneath RabbitMQ quorum queues), a leader election can stall indefinitely even when a majority of cluster members are alive and communicating.

## Observable behavior

- After a leader loss event (e.g., a planned node maintenance window that takes down the minority), the cluster periodically attempts elections but never produces a new leader.
- Cluster members cycle through repeated state transitions visible in Ra log output. No member ever reaches `leader` state.
- From the client side (e.g., a RabbitMQ quorum queue), the queue becomes permanently unavailable: publishes and consumes time out or return errors indicating no leader is available.
- The cluster does not crash. Individual nodes remain responsive to inspection commands. The livelock is a pure liveness failure.
- Observed across multiple Ra versions; became more likely when cluster membership changes or maintenance windows precede the leader loss event.
