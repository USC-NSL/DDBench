# Symptom

When a Kvrocks replica is connected to a master via incremental replication, the replica intermittently stalls for minutes to hours after receiving a large batch of data, even though the replication connection remains up and no errors appear in the logs.

## Observable behavior
- After a large write batch (e.g., 16 KB or more) propagates to the replica, subsequent small writes on the master do not appear on the replica for an extended period (minutes to hours).
- The replication connection shows `master_link_status:up` on the replica, and no error messages appear in either master or replica logs.
- The `INFO replication` command on the master shows a growing offset gap between master and replica (e.g., `master_repl_offset:11945` vs. replica at `11918`), confirming data is not flowing despite the connection being healthy.
- Restarting either master or replica immediately resolves the stall and replication resumes normally.
- The problem is highly reproducible under cross-region or high-latency network conditions, and can also be triggered locally by writing a large value followed by small values.
- The stall only affects incremental replication (post-fullsync); the initial full sync completes successfully.
