# Oracle validation

Every case's oracle was checked with `./bench.sh validate-oracle <case> --runs N`:
the pristine buggy worktree must FAIL in all N runs, and the worktree with
`cases-solution/<case>/gold.patch` applied must PASS in all N runs. Runs use the
normal scoring path (`bench.sh reproduce`: incremental rebuild, then the oracle,
offline with the case's dependency cache).

| Status | Meaning |
|--------|---------|
| SOUND | buggy FAIL N/N and gold PASS N/N |
| FLAKY | mixed results on at least one side |
| UNSOUND | buggy never FAILs or gold never PASSes |
| ERROR | a run returned ERROR, or gold.patch does not apply |
| NO-GOLD | no gold.patch (buggy side only) |
| NOT-RUN | not validated in this run (see note) |

Machine-readable results: [`registry/oracle_validation.json`](../registry/oracle_validation.json).

Environment: 2026-10-14; bench.sh validate-oracle --runs 3 (3 buggy + 3 gold runs per case), offline scoring; 64-core x86_64 host, Docker 29.9.0, 10 CPUs per case container, 6-9 cases validated concurrently.

## Summary

| Status | Cases |
|--------|------:|
| SOUND | 60 |
| **Total** | **60** |

## Per case

| Case | Status | Buggy FAIL | Gold PASS | Duration (s) | Date | Note |
|------|--------|-----------:|----------:|-------------:|------|------|
| `bookkeeper-2614-recovery-fencing-gap` | SOUND | 3/3 | 3/3 | 712 | 2026-10-14 |  |
| `bookkeeper-4701-fencing-race` | SOUND | 3/3 | 3/3 | 632 | 2026-10-14 |  |
| `consul-12295-acl-replication-stall` | SOUND | 3/3 | 3/3 | 31 | 2026-10-14 |  |
| `consul-8377-snapshot-restore-index` | SOUND | 3/3 | 3/3 | 86 | 2026-10-14 |  |
| `consul-9772-streaming-snapshot-cache` | SOUND | 3/3 | 3/3 | 26 | 2026-10-14 |  |
| `dragonfly-6614-monitor-multiexec` | SOUND | 3/3 | 3/3 | 146 | 2026-10-14 |  |
| `dragonfly-6619-evalsha-empty` | SOUND | 3/3 | 3/3 | 133 | 2026-10-14 |  |
| `dragonfly-6654-mc-reply-large` | SOUND | 3/3 | 3/3 | 88 | 2026-10-14 |  |
| `dragonfly-6687-replica-rdb-encoding` | SOUND | 3/3 | 3/3 | 382 | 2026-10-14 |  |
| `dragonfly-6738-pipeline-block` | SOUND | 3/3 | 3/3 | 207 | 2026-10-14 | Symptom and docs aligned with the fixed bug (pipelined blocking commands) on 2026-10-14; oracle extended with a pipelined BRPOPLPUSH wake-up check. Validated after `clean` + `setup`. |
| `dragonfly-6753-populate-sigfpe` | SOUND | 3/3 | 3/3 | 107 | 2026-10-14 |  |
| `dragonfly-6761-mc-pipeline-crash` | SOUND | 3/3 | 3/3 | 134 | 2026-10-14 |  |
| `dragonfly-6764-hincrbyfloat-nan` | SOUND | 3/3 | 3/3 | 107 | 2026-10-14 |  |
| `dragonfly-6819-stale-expiry` | SOUND | 3/3 | 3/3 | 122 | 2026-10-14 |  |
| `dragonfly-6825-config-overflow` | SOUND | 3/3 | 3/3 | 103 | 2026-10-14 |  |
| `dragonfly-6856-flushslots-oob` | SOUND | 3/3 | 3/3 | 225 | 2026-10-14 |  |
| `dragonfly-6907-ftsearch-vector-crash` | SOUND | 3/3 | 3/3 | 123 | 2026-10-14 |  |
| `dragonfly-6909-search-nonfinite` | SOUND | 3/3 | 3/3 | 114 | 2026-10-14 |  |
| `dragonfly-6912-rdb-encoding` | SOUND | 3/3 | 3/3 | 146 | 2026-10-14 |  |
| `etcd-17158-delete-linearizability` | SOUND | 3/3 | 3/3 | 72 | 2026-10-14 |  |
| `etcd-17529-watch-compaction-loss` | SOUND | 3/3 | 3/3 | 74 | 2026-10-14 |  |
| `etcd-19172-embed-data-race` | SOUND | 3/3 | 3/3 | 1930 | 2026-10-14 |  |
| `etcd-19179-watch-tombstone-compact` | SOUND | 3/3 | 3/3 | 93 | 2026-10-14 |  |
| `etcd-20221-watch-restore-revision` | SOUND | 3/3 | 3/3 | 114 | 2026-10-14 |  |
| `etcd-20704-leasing-linearizability` | SOUND | 3/3 | 3/3 | 120 | 2026-10-14 |  |
| `etcd-20893-force-new-cluster-learner` | SOUND | 3/3 | 3/3 | 238 | 2026-10-14 |  |
| `kafka-14334-delayed-fetch-purgatory` | SOUND | 3/3 | 3/3 | 582 | 2026-10-15 | Oracle redesigned on 2026-10-15: two in-process brokers with fetching from followers enabled; a consumer fetch waiting on the follower must be answered with the produced record within 10 s of its acknowledgement (replaces a mocked unit test whose verdict reduced to whether `ReplicaFetcherThread` overrides `doWork()`). Validated after `clean` + `setup`. |
| `kafka-15170-endless-rebalance-loop` | SOUND | 3/3 | 3/3 | 496 | 2026-10-14 |  |
| `kafka-15784-txn-offset-atomicity` | SOUND | 3/3 | 3/3 | 432 | 2026-10-14 | Oracle redesigned on 2026-10-14 (transactional offset commit racing group deletion or an offsets-partition reload); build narrowed to `:core:jar`. Validated after `clean` + `setup`. |
| `kvrocks-2214-slave-sync-gap` | SOUND | 3/3 | 3/3 | 773 | 2026-10-14 |  |
| `kvrocks-2512-slaveof-deadlock` | SOUND | 3/3 | 3/3 | 1641 | 2026-10-14 |  |
| `kvrocks-2520-namespace-fullsync` | SOUND | 3/3 | 3/3 | 1056 | 2026-10-14 |  |
| `kvrocks-3148-namespace-delete` | SOUND | 3/3 | 3/3 | 911 | 2026-10-14 |  |
| `kvrocks-3208-replication-watermark` | SOUND | 3/3 | 3/3 | 994 | 2026-10-14 |  |
| `kvrocks-3315-zdiff-crash` | SOUND | 3/3 | 3/3 | 1058 | 2026-10-14 |  |
| `kvrocks-3339-xreadgroup-double` | SOUND | 3/3 | 3/3 | 1017 | 2026-10-14 |  |
| `kvrocks-3356-replication-wal` | SOUND | 3/3 | 3/3 | 1314 | 2026-10-15 | Migrated to the standard oracle layout on 2026-10-14 (standard prelude, `rebuild_worktree`, `mktemp` run directory; verdict logic unchanged) and given a `gold.patch` (the `src/` part of the fix commit). Validated on 2026-10-15 after `clean` + `setup`, with no other validation running. |
| `nats-6374-consumer-stuck-redelivery` | SOUND | 3/3 | 3/3 | 109 | 2026-10-14 |  |
| `nats-6455-reserved-resource-leak` | SOUND | 3/3 | 3/3 | 112 | 2026-10-14 |  |
| `nats-7308-delete-nonexistent-reset` | SOUND | 3/3 | 3/3 | 136 | 2026-10-14 |  |
| `nats-7707-wq-consumer-map-crash` | SOUND | 3/3 | 3/3 | 296 | 2026-10-14 |  |
| `nats-7718-subscription-leak` | SOUND | 3/3 | 3/3 | 114 | 2026-10-14 |  |
| `nats-7726-mixed-filter` | SOUND | 3/3 | 3/3 | 99 | 2026-10-14 |  |
| `nats-7760-filter-stepdown` | SOUND | 3/3 | 3/3 | 115 | 2026-10-14 |  |
| `nats-7817-workqueue-message-loss` | SOUND | 3/3 | 3/3 | 100 | 2026-10-14 |  |
| `nats-7852-filter-perf` | SOUND | 3/3 | 3/3 | 80 | 2026-10-14 |  |
| `ra-439-election-livelock` | SOUND | 3/3 | 3/3 | 217 | 2026-10-14 |  |
| `rabbitmq-12635-qq-snapshot-crash` | SOUND | 3/3 | 3/3 | 309 | 2026-10-14 |  |
| `raft-268-shutdown-deadlock` | SOUND | 3/3 | 3/3 | 105 | 2026-10-14 |  |
| `raft-358-negative-log-range` | SOUND | 3/3 | 3/3 | 11 | 2026-10-14 |  |
| `raft-460-logcache-store-order` | SOUND | 3/3 | 3/3 | 16 | 2026-10-14 |  |
| `raft-517-candidate-appendentries-race` | SOUND | 3/3 | 3/3 | 243 | 2026-10-14 |  |
| `raft-581-transfer-write-race` | SOUND | 3/3 | 3/3 | 2505 | 2026-10-14 |  |
| `raft-609-prevote-contact-liveness` | SOUND | 3/3 | 3/3 | 68 | 2026-10-14 |  |
| `raft-rs-221-campaign-conf-change` | SOUND | 3/3 | 3/3 | 54 | 2026-10-14 |  |
| `raft-rs-345-readindex-config-change` | SOUND | 3/3 | 3/3 | 54 | 2026-10-14 |  |
| `rocksdb-10751-stalled-writes-shutdown` | SOUND | 3/3 | 3/3 | 173 | 2026-10-14 |  |
| `zookeeper-4643-sync-epoch-ordering` | SOUND | 3/3 | 3/3 | 359 | 2026-10-14 |  |
| `zookeeper-4846-fuzzy-snapshot-acl` | SOUND | 3/3 | 3/3 | 357 | 2026-10-14 |  |
| `zookeeper-4925-diff-sync-committedlog-hole` | SOUND | 3/3 | 3/3 | 372 | 2026-10-14 |  |

## Notes

- All runs were offline (`--network none`) against each case's dependency cache, which `bench.sh setup` filled by building and running the oracle once with network access.
- A first pass on 13 cases found one ERROR. In `nats-7760-filter-stepdown`, creating the R5 consumer on a freshly formed 5-node cluster timed out once. The oracle now retries consumer creation (idempotent), as it already did for stream creation. The case was SOUND in the run above.
- One setup hit a transient Go toolchain download error from proxy.golang.org (`nats-7707-wq-consumer-map-crash`). `bench.sh setup` now retries its online build once. The rerun was SOUND.
- Timing- and race-based oracles (for example `raft-517`, `raft-581`, `etcd-19172`, `kvrocks-2512`, `kvrocks-3208`, `nats-7852`, `rocksdb-10751`, `zookeeper-4643`) were validated under the load of 6–9 concurrent validations, with the same 3+3 runs as every other case. Re-run them with more runs (`--runs 10`) on the hardware you evaluate on.
- `kafka-15784-txn-offset-atomicity` and `dragonfly-6738-pipeline-block` were reworked and validated separately on 2026-10-14. Each was run from a clean slate (`bench.sh clean` + `setup`) with `--runs 3`, with the two cases validating concurrently. Negative controls (`bench.sh eval --patch`) all FAILed: for `kafka-15784`, a partial fix that refuses `DeleteGroups` while a transactional offset commit is pending (it passes the group-deletion scenario but fails the coordinator-reload one) and a stub that acknowledges every `TxnOffsetCommit` without writing it; for `dragonfly-6738`, a partial fix that sends pending replies only before `BLPOP` (it fails the pipelined `BRPOPLPUSH` check).
- `kvrocks-3356-replication-wal` was migrated and validated separately (see its note). Buggy runs took about 210 s each (about 120 s of rebuild plus the 90 s observation window); gold runs detached the stalled replica after about 30 s in every run.
- `kafka-14334-delayed-fetch-purgatory` was reworked and validated separately on 2026-10-15, from a clean slate (`bench.sh clean` + `setup`) with `--runs 3` and no other validation running. In the buggy runs the follower answered the waiting consumer fetch only when its 30 s `maxWait` expired (30.0 s after the fetch was sent, about 28.4 s after the record was acknowledged). In the gold runs it answered about 0.5 s after the acknowledgement, in both rounds (deadline 10 s). Negative controls (`bench.sh eval --patch`) all FAILed: a no-op `ReplicaFetcherThread.doWork()` override, a `completeDelayedFetchRequests` method with an empty body called from `doWork()`, and a broker that answers consumer fetches on a follower without waiting. An alternative fix, which completes the follower's delayed fetches directly in `processPartitionData()` when the high watermark advances, PASSed 3/3.
