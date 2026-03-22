# Bug Cases Index
## Distributed Interactive Debugger Evaluation

**Total cases: 60**
**Generated: 2026-03-21**

Each entry maps to a folder in `cases/<folder_name>/` (setup, symptom, reproduce, verification) and `cases-solution/<folder_name>/` (solution).

---

| Rank | Project | GitHub URL | Bug Description | Folder Name |
|------|---------|-----------|-----------------|-------------|
| 1 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6856 | Cluster FLUSHSLOTS with slot ID >= 16384 causes out-of-bounds crash | `dragonfly-6856-flushslots-oob` |
| 2 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6825 | Cluster CONFIG parsing integer overflow causes crash | `dragonfly-6825-config-overflow` |
| 3 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6753 | DEBUG POPULATE with val_size=0 causes SIGFPE division by zero | `dragonfly-6753-populate-sigfpe` |
| 4 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6619 | EVALSHA with empty SHA string causes assertion failure crash | `dragonfly-6619-evalsha-empty` |
| 5 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6761 | Memcache STATS/VERSION in pipeline causes crash | `dragonfly-6761-mc-pipeline-crash` |
| 6 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6614 | Double MONITOR inside MULTI/EXEC causes assertion crash | `dragonfly-6614-monitor-multiexec` |
| 7 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6907 | FT.SEARCH crashes on wrong-sized vector/numeric field values | `dragonfly-6907-ftsearch-vector-crash` |
| 8 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6764 | HINCRBYFLOAT with inf/NaN creates invalid hash state and crashes | `dragonfly-6764-hincrbyfloat-nan` |
| 9 | Kvrocks | https://github.com/apache/kvrocks/issues/3315 | ZDIFF with numkeys=0 crashes due to out-of-bounds access | `kvrocks-3315-zdiff-crash` |
| 10 | NATS Server | https://github.com/nats-io/nats-server/issues/7760 | Consumer filter subjects stop matching after leader step-down | `nats-7760-filter-stepdown` |
| 11 | etcd | https://github.com/etcd-io/etcd/issues/20893 | --force-new-cluster fails to remove learner members after snapshot | `etcd-20893-force-new-cluster-learner` |
| 12 | etcd | https://github.com/etcd-io/etcd/issues/19172 | Data race between Close() and errHandler() in embedded etcd | `etcd-19172-embed-data-race` |
| 13 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6909 | Non-finite NUMERIC values and KeepTopKSorted OOB crash search | `dragonfly-6909-search-nonfinite` |
| 14 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6654 | Memcache meta get reply exceeds buffer size for large values | `dragonfly-6654-mc-reply-large` |
| 15 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6819 | Overwriting key without expiry leaves stale expiry entry causing crash | `dragonfly-6819-stale-expiry` |
| 16 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6766 | JSON operations create orphaned objects corrupting memory tracking | `dragonfly-6766-json-orphans` |
| 17 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6912 | Unknown encoding for type 17 in rdb_save during DUMP command | `dragonfly-6912-rdb-encoding` |
| 18 | Kvrocks | https://github.com/apache/kvrocks/issues/3148 | NAMESPACE SET with another namespace's token deletes that namespace | `kvrocks-3148-namespace-delete` |
| 19 | NATS Server | https://github.com/nats-io/nats-server/issues/7817 | Messages lost with JetStream WorkQueue retention and R3 on max-deliver | `nats-7817-workqueue-message-loss` |
| 20 | NATS Server | https://github.com/nats-io/nats-server/issues/7726 | Consumer with mixed wildcard/literal filter subjects fails delivery | `nats-7726-mixed-filter` |
| 21 | etcd | https://github.com/etcd-io/etcd/issues/20655 | Fast watch creation breaks reliable watch guarantee, drops events | `etcd-20655-fast-watch` |
| 22 | etcd | https://github.com/etcd-io/etcd/issues/20704 | Multiple linearizability bugs in client/v3/leasing cache | `etcd-20704-leasing-linearizability` |
| 23 | hashicorp/raft | https://github.com/hashicorp/raft/issues/358 | Snapshot log compaction attempts DeleteRange with max < min | `raft-358-negative-log-range` |
| 24 | ClickHouse | https://github.com/ClickHouse/ClickHouse/issues/92375 | DISTINCT over distributed table returns wrong count with optimize_skip_unused_shards | `clickhouse-92375-distinct-distributed` |
| 25 | ClickHouse | https://github.com/ClickHouse/ClickHouse/issues/99109 | sum(Float64) GROUP BY produces different results with different max_threads | `clickhouse-99109-sum-nondeterministic` |
| 26 | ClickHouse | https://github.com/ClickHouse/ClickHouse/issues/43816 | Deadlock in ReplicatedMergeTreeQueue between queue lock and background executor | `clickhouse-43816-replicated-deadlock` |
| 27 | Seastar | https://github.com/scylladb/seastar/issues/2202 | Cross-shard realloc to smaller size crashes with assertion failure | `seastar-2202-cross-shard-realloc` |
| 28 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6822 | 100% CPU and unresponsive during periodic key expiration | `dragonfly-6822-expiry-cpu` |
| 29 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6738 | BRPOPLPUSH not woken when RPUSH happens inside Lua EVAL script | `dragonfly-6738-pipeline-block` |
| 30 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6687 | Replica sync fails with unknown RDB encoding 62 and retries in loop | `dragonfly-6687-replica-rdb-encoding` |
| 31 | Kvrocks | https://github.com/apache/kvrocks/issues/3356 | Replication feed thread blocks on slow consumer causing WAL exhaustion | `kvrocks-3356-replication-wal` |
| 32 | Kvrocks | https://github.com/apache/kvrocks/issues/3339 | XREADGROUP BLOCK sends double response under concurrent load | `kvrocks-3339-xreadgroup-double` |
| 33 | hashicorp/raft | https://github.com/hashicorp/raft/issues/212 | Out-of-date followers stuck in snapshot install retry loop | `raft-212-follower-snapshot-loop` |
| 34 | hashicorp/raft | https://github.com/hashicorp/raft/issues/291 | Failed node causes OOM via verifyLeader future leak | `raft-291-oom-verifyleader` |
| 35 | CockroachDB | https://github.com/cockroachdb/cockroach/issues/166122 | Concurrent update during partial index backfill causes data loss and phantom rows | `cockroachdb-166122-partial-index-dataloss` |
| 36 | NATS Server | https://github.com/nats-io/nats-server/issues/7718 | JetStream leaks subscriptions with overlapping stream imports and OrderedConsumer churn | `nats-7718-subscription-leak` |
| 37 | NATS Server | https://github.com/nats-io/nats-server/issues/6888 | JetStream stream completely lost after kill -9 and restart | `nats-6888-stream-lost-kill9` |
| 38 | ClickHouse | https://github.com/ClickHouse/ClickHouse/issues/75699 | LOGICAL_ERROR when JOINing Merge table over Distributed table | `clickhouse-75699-join-merge-distributed` |
| 39 | ClickHouse | https://github.com/ClickHouse/ClickHouse/issues/78074 | Invalid number of rows in Chunk with Distributed table and JOIN | `clickhouse-78074-distributed-chunk-rows` |
| 40 | ClickHouse | https://github.com/ClickHouse/ClickHouse/issues/29332 | Predicate pushdown incorrectly rewrites queries with distributed IN subqueries | `clickhouse-29332-predicate-pushdown` |
| 41 | ClickHouse | https://github.com/ClickHouse/ClickHouse/issues/40571 | ClickHouse Keeper crashes on every startup with segfault 11 | `clickhouse-40571-keeper-segfault` |
| 42 | ClickHouse | https://github.com/ClickHouse/ClickHouse/issues/98079 | Keeper disconnects client after addWatch() breaking Java ZK CuratorCache | `clickhouse-98079-keeper-addwatch` |
| 43 | ClickHouse | https://github.com/ClickHouse/ClickHouse/issues/44865 | Background merges stuck permanently on replicated tables requiring restart | `clickhouse-44865-merge-stuck` |
| 44 | Redpanda | https://github.com/redpanda-data/redpanda/issues/25769 | ListOffsets returns incorrect results for compressed batches | `redpanda-25769-listoffsets-wrong` |
| 45 | ScyllaDB | https://github.com/scylladb/scylladb/issues/27130 | Segfault when calling raft_topology/reload REST API during node startup | `scylladb-27130-reload-segfault` |
| 46 | Nomad | https://github.com/hashicorp/nomad/issues/27567 | Scheduler panics with nil pointer dereference in system job deployment | `nomad-27567-scheduler-panic` |
| 47 | hashicorp/raft | https://github.com/hashicorp/raft/issues/268 | Raft.Shutdown() deadlocks with concurrent takeSnapshot() | `raft-268-shutdown-deadlock` |
| 48 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6862 | Crash in db_slice.cc during concurrent operations in cluster mode | `dragonfly-6862-dbslice-concurrent` |
| 49 | etcd | https://github.com/etcd-io/etcd/issues/20657 | Race between snapshot cleanup and application causes follower panic | `etcd-20657-snapshot-cleanup-race` |
| 50 | etcd | https://github.com/etcd-io/etcd/issues/20269 | Panic on member rejoin after reset — tocommit out of range | `etcd-20269-rejoin-panic` |
| 51 | etcd | https://github.com/etcd-io/etcd/issues/20793 | Learner promotion not persisted into v3store across multiple upgrades | `etcd-20793-learner-upgrade` |
| 52 | NATS Server | https://github.com/nats-io/nats-server/issues/7852 | Consumer subject filtering causes >20% performance degradation even when matching all | `nats-7852-filter-perf` |
| 53 | Redpanda | https://github.com/redpanda-data/redpanda/issues/15118 | ss::future assert under load when kafka client authentication fails | `redpanda-15118-future-assert` |
| 54 | Redpanda | https://github.com/redpanda-data/redpanda/issues/16944 | Oversized allocation (262KB) in raft::replicate_batcher::flush | `redpanda-16944-raft-batcher-alloc` |
| 55 | ScyllaDB | https://github.com/scylladb/scylladb/issues/28200 | Use-after-free in streaming_task_impl::run from coroutine::lambda | `scylladb-28200-uaf-streaming` |
| 56 | ScyllaDB | https://github.com/scylladb/scylladb/issues/25173 | Truncate concurrent-write check exits raft applier fiber permanently | `scylladb-25173-truncate-raft-exit` |
| 57 | RocksDB | https://github.com/facebook/rocksdb/issues/10751 | Stalled writes block forever during DB::Close() shutdown | `rocksdb-10751-stalled-writes-shutdown` |
| 58 | RocksDB | https://github.com/facebook/rocksdb/issues/13652 | Checkpoint::ExportColumnFamily occasionally misses committed data | `rocksdb-13652-export-cf-missing-data` |
| 59 | ScyllaDB | https://github.com/scylladb/scylladb/issues/28057 | Raft topology IP-to-ID mapping for replacing node not preserved on restart | `scylladb-28057-ip-id-mapping` |
| 60 | ScyllaDB | https://github.com/scylladb/scylladb/issues/27956 | Staging SSTables not discovered on restart causing permanent base-view inconsistency | `scylladb-27956-staging-sstable` |
