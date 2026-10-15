# Bug Cases Index

**Total cases: 60** (13 projects) · **Updated: 2026-10-14**

Every case is built and run in Docker by `bench.sh` from the repository root:

```bash
./bench.sh setup <folder_name>       # build image + case repository, warm dependency caches
./bench.sh reproduce <folder_name>   # oracle: exit 0 = PASS (fixed), 1 = FAIL (bug present), 2 = ERROR
```

Oracle soundness (buggy FAIL / gold patch PASS) for every case is recorded in
[`docs/oracle-validation.md`](docs/oracle-validation.md). Tiers are defined in
[`registry/tier_definitions.md`](registry/tier_definitions.md).

---

| # | Project | Upstream issue | Bug description | Folder name | Tier |
|---|---------|----------------|-----------------|-------------|------|
| 1 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6856 | Cluster FLUSHSLOTS with slot ID >= 16384 causes out-of-bounds crash | `dragonfly-6856-flushslots-oob` | tier3 |
| 2 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6825 | Cluster CONFIG parsing integer overflow causes crash | `dragonfly-6825-config-overflow` | tier3 |
| 3 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6753 | DEBUG POPULATE with val_size=0 causes SIGFPE division by zero | `dragonfly-6753-populate-sigfpe` | tier3 |
| 4 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6619 | EVALSHA with empty SHA string causes assertion failure crash | `dragonfly-6619-evalsha-empty` | tier3 |
| 5 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6761 | Memcache STATS/VERSION in pipeline causes crash | `dragonfly-6761-mc-pipeline-crash` | tier3 |
| 6 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6614 | Double MONITOR inside MULTI/EXEC causes assertion crash | `dragonfly-6614-monitor-multiexec` | tier3 |
| 7 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6907 | FT.SEARCH crashes on wrong-sized vector/numeric field values | `dragonfly-6907-ftsearch-vector-crash` | tier3 |
| 8 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6764 | HINCRBYFLOAT with inf/NaN creates invalid hash state and crashes | `dragonfly-6764-hincrbyfloat-nan` | tier3 |
| 9 | Kvrocks | https://github.com/apache/kvrocks/issues/3315 | ZDIFF with numkeys=0 crashes due to out-of-bounds access | `kvrocks-3315-zdiff-crash` | tier3 |
| 10 | NATS Server | https://github.com/nats-io/nats-server/issues/7760 | Consumer filter subjects stop matching after leader step-down | `nats-7760-filter-stepdown` | tier1 |
| 11 | etcd | https://github.com/etcd-io/etcd/issues/20893 | --force-new-cluster fails to remove learner members after snapshot | `etcd-20893-force-new-cluster-learner` | tier1 |
| 12 | etcd | https://github.com/etcd-io/etcd/issues/19172 | Data race between Close() and errHandler() in embedded etcd | `etcd-19172-embed-data-race` | tier2 |
| 13 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6909 | Non-finite NUMERIC values and KeepTopKSorted OOB crash search | `dragonfly-6909-search-nonfinite` | tier3 |
| 14 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6654 | Memcache meta get reply exceeds buffer size for large values | `dragonfly-6654-mc-reply-large` | tier3 |
| 15 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6819 | Overwriting key without expiry leaves stale expiry entry causing crash | `dragonfly-6819-stale-expiry` | tier3 |
| 16 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6912 | Unknown encoding for type 17 in rdb_save during DUMP command | `dragonfly-6912-rdb-encoding` | tier3 |
| 17 | Kvrocks | https://github.com/apache/kvrocks/issues/3148 | NAMESPACE SET with another namespace's token deletes that namespace | `kvrocks-3148-namespace-delete` | tier2 |
| 18 | NATS Server | https://github.com/nats-io/nats-server/issues/7817 | Messages lost with JetStream WorkQueue retention and R3 on max-deliver | `nats-7817-workqueue-message-loss` | tier1 |
| 19 | NATS Server | https://github.com/nats-io/nats-server/issues/7726 | Consumer with mixed wildcard/literal filter subjects fails delivery | `nats-7726-mixed-filter` | tier2 |
| 20 | etcd | https://github.com/etcd-io/etcd/issues/20704 | Multiple linearizability bugs in client/v3/leasing cache | `etcd-20704-leasing-linearizability` | tier2 |
| 21 | hashicorp/raft | https://github.com/hashicorp/raft/issues/358 | Snapshot log compaction attempts DeleteRange with max < min | `raft-358-negative-log-range` | tier2 |
| 22 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6738 | Pipelined replies held back until a blocking BLPOP/BRPOPLPUSH in the pipeline finishes | `dragonfly-6738-pipeline-block` | tier2 |
| 23 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6687 | Replica sync fails with unknown RDB encoding 62 and retries in loop | `dragonfly-6687-replica-rdb-encoding` | tier1 |
| 24 | Kvrocks | https://github.com/apache/kvrocks/issues/3356 | Replication feed thread blocks on slow consumer causing WAL exhaustion | `kvrocks-3356-replication-wal` | tier1 |
| 25 | Kvrocks | https://github.com/apache/kvrocks/issues/3339 | XREADGROUP BLOCK sends double response under concurrent load | `kvrocks-3339-xreadgroup-double` | tier2 |
| 26 | NATS Server | https://github.com/nats-io/nats-server/issues/7718 | JetStream leaks subscriptions with overlapping stream imports and OrderedConsumer churn | `nats-7718-subscription-leak` | tier1 |
| 27 | hashicorp/raft | https://github.com/hashicorp/raft/issues/268 | Raft.Shutdown() deadlocks with concurrent takeSnapshot() | `raft-268-shutdown-deadlock` | tier1 |
| 28 | NATS Server | https://github.com/nats-io/nats-server/issues/7852 | Consumer subject filtering causes >20% performance degradation even when matching all | `nats-7852-filter-perf` | tier2 |
| 29 | RocksDB | https://github.com/facebook/rocksdb/issues/10751 | Stalled writes block forever during DB::Close() shutdown | `rocksdb-10751-stalled-writes-shutdown` | tier3 |
| 30 | Kvrocks | https://github.com/apache/kvrocks/issues/2520 | Namespaces not loaded into memory after full sync from master | `kvrocks-2520-namespace-fullsync` | tier1 |
| 31 | Kvrocks | https://github.com/apache/kvrocks/issues/2214 | Slave misses key updates during downtime due to replication offset drift | `kvrocks-2214-slave-sync-gap` | tier1 |
| 32 | hashicorp/raft | https://github.com/hashicorp/raft/issues/517 | Data race between candidate state exit and AppendEntries handler | `raft-517-candidate-appendentries-race` | tier2 |
| 33 | hashicorp/raft | https://github.com/hashicorp/raft/pull/581 | Leadership transfer fails when writes advance log during transfer window | `raft-581-transfer-write-race` | tier1 |
| 34 | etcd | https://github.com/etcd-io/etcd/issues/20221 | Watch on future revision receives old events after snapshot restore | `etcd-20221-watch-restore-revision` | tier1 |
| 35 | NATS Server | https://github.com/nats-io/nats-server/issues/7707 | Concurrent map crash in WorkQueue consumer partition management | `nats-7707-wq-consumer-map-crash` | tier2 |
| 36 | Kvrocks | https://github.com/apache/kvrocks/issues/3208 | Replication stalls after large batch due to stuck read watermark | `kvrocks-3208-replication-watermark` | tier1 |
| 37 | Consul | https://github.com/hashicorp/consul/issues/8377 | Snapshot restore loses node/service/check CreateIndex across replicas | `consul-8377-snapshot-restore-index` | tier1 |
| 38 | etcd | https://github.com/etcd-io/etcd/issues/17529 | Watch event loss after compaction when watcher channel is full | `etcd-17529-watch-compaction-loss` | tier1 |
| 39 | etcd | https://github.com/etcd-io/etcd/issues/19179 | Missing delete event on watch after compaction removes all put revisions | `etcd-19179-watch-tombstone-compact` | tier1 |
| 40 | hashicorp/raft | https://github.com/hashicorp/raft/pull/609 | Pre-vote refreshes last-contact timestamp blocking new elections | `raft-609-prevote-contact-liveness` | tier1 |
| 41 | NATS Server | https://github.com/nats-io/nats-server/issues/6374 | Consumer stuck and slow after leader step-down with pending redeliveries | `nats-6374-consumer-stuck-redelivery` | tier1 |
| 42 | Kvrocks | https://github.com/apache/kvrocks/issues/2512 | Deadlock when switching master frequently via SLAVEOF | `kvrocks-2512-slaveof-deadlock` | tier2 |
| 43 | NATS Server | https://github.com/nats-io/nats-server/issues/6455 | Reserved disk resources double-counted after cluster state reset | `nats-6455-reserved-resource-leak` | tier2 |
| 44 | NATS Server | https://github.com/nats-io/nats-server/issues/7308 | Deleting non-existent message triggers cluster state reset and stream unavailability | `nats-7308-delete-nonexistent-reset` | tier1 |
| 45 | etcd | https://github.com/etcd-io/etcd/issues/17158 | UnsafeDelete breaks linearizability due to buffered read seeing stale data | `etcd-17158-delete-linearizability` | tier1 |
| 46 | Consul | https://github.com/hashicorp/consul/pull/9772 | Streaming event publisher caches framing event in snapshot corrupting fresh subscribers | `consul-9772-streaming-snapshot-cache` | tier1 |
| 47 | tikv/raft-rs | https://github.com/tikv/raft-rs/issues/345 | ReadIndex requests stall after quorum shrinks on configuration change | `raft-rs-345-readindex-config-change` | tier2 |
| 48 | RabbitMQ | https://github.com/rabbitmq/rabbitmq-server/issues/12635 | Quorum queue member crashes after Raft snapshot installation (stale log read) | `rabbitmq-12635-qq-snapshot-crash` | tier1 |
| 49 | BookKeeper | https://github.com/apache/bookkeeper/pull/4701 | Fencing bypassed due to race in HandleFactory causing entry loss | `bookkeeper-4701-fencing-race` | tier1 |
| 50 | hashicorp/raft | https://github.com/hashicorp/raft/issues/429 | LogCache caches entries before StoreLogs causing phantom data on restart (issue #429; fix PR #460) | `raft-460-logcache-store-order` | tier1 |
| 51 | Consul | https://github.com/hashicorp/consul/issues/12295 | ACL replication permanently stalls after same-server leadership re-election | `consul-12295-acl-replication-stall` | tier2 |
| 52 | Ra | https://github.com/rabbitmq/ra/issues/439 | Election livelock when candidate has lower log index than pre-vote member | `ra-439-election-livelock` | tier1 |
| 53 | BookKeeper | https://github.com/apache/bookkeeper/pull/2616 | Recovery reads missing fencing flag allow original writer to commit after ledger close | `bookkeeper-2614-recovery-fencing-gap` | tier1 |
| 54 | tikv/raft-rs | https://github.com/tikv/raft-rs/issues/221 | Node campaigns via leader transfer despite pending unapplied conf change | `raft-rs-221-campaign-conf-change` | tier2 |
| 55 | ZooKeeper | https://issues.apache.org/jira/browse/ZOOKEEPER-4643 | Follower persists uncommitted proposals before updating epoch during ZAB sync | `zookeeper-4643-sync-epoch-ordering` | tier1 |
| 56 | ZooKeeper | https://issues.apache.org/jira/browse/ZOOKEEPER-4925 | Stale follower propagates committedLog hole after DIFF sync becoming leader | `zookeeper-4925-diff-sync-committedlog-hole` | tier1 |
| 57 | ZooKeeper | https://issues.apache.org/jira/browse/ZOOKEEPER-4846 | Fuzzy snapshot ACL cache race causes fatal RuntimeException on restart | `zookeeper-4846-fuzzy-snapshot-acl` | tier1 |
| 58 | Kafka | https://issues.apache.org/jira/browse/KAFKA-15784 | Transactional offset commit racing group deletion or offsets-partition reload diverges from the log | `kafka-15784-txn-offset-atomicity` | tier1 |
| 59 | Kafka | https://issues.apache.org/jira/browse/KAFKA-14334 | Delayed fetch purgatory not completed on follower replica append | `kafka-14334-delayed-fetch-purgatory` | tier1 |
| 60 | Kafka | https://issues.apache.org/jira/browse/KAFKA-15170 | CooperativeStickyAssignor endless rebalance loop with rack-aware balancing | `kafka-15170-endless-rebalance-loop` | tier1 |
