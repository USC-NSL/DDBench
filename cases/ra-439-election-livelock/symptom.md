# Symptom

In a Ra Raft cluster (used as the consensus layer beneath RabbitMQ quorum queues), a leader election can stall indefinitely even when a majority of cluster members are alive and communicating.

## Observable behavior

- After a leader loss event (e.g., a planned node maintenance window that takes down the minority), the cluster periodically attempts elections but never produces a new leader.
- Cluster members cycle through state transitions (`follower → pre_vote → candidate → follower → ...`) indefinitely, visible in Ra log output. No member ever reaches `leader` state.
- From the client side (e.g., a RabbitMQ quorum queue), the queue becomes permanently unavailable: publishes and consumes time out or return errors indicating no leader is available.
- The condition only manifests with a specific interleaving: one member has entered `candidate` state (and therefore has a higher term) while another member is still in `pre_vote` state with a fresher log (higher log index). In this combination, the candidate cannot win the election (because the pre_vote member has a longer log and will not grant a vote), and the pre_vote member cannot get enough votes to become a candidate (because the candidate treats it as a lower-priority peer).
- The cluster does not crash. Individual nodes remain responsive to inspection commands. The livelock is a pure liveness failure.
- Observed across multiple Ra versions; became more common when cluster membership changes or maintenance windows create specific log-index disparities between members.
