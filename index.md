# Bug Cases Index
## Distributed Interactive Debugger Evaluation

**Total verified cases: 37**
**Updated: 2026-03-27**

Each case has `./setup.sh` and `./reproduce.sh` scripts that build from source on Ubuntu 24.04 and reliably reproduce the bug. Run `cd cases/<folder_name>/ && ./setup.sh && ./reproduce.sh`.

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
| 16 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6912 | Unknown encoding for type 17 in rdb_save during DUMP command | `dragonfly-6912-rdb-encoding` |
| 17 | Kvrocks | https://github.com/apache/kvrocks/issues/3148 | NAMESPACE SET with another namespace's token deletes that namespace | `kvrocks-3148-namespace-delete` |
| 18 | NATS Server | https://github.com/nats-io/nats-server/issues/7817 | Messages lost with JetStream WorkQueue retention and R3 on max-deliver | `nats-7817-workqueue-message-loss` |
| 19 | NATS Server | https://github.com/nats-io/nats-server/issues/7726 | Consumer with mixed wildcard/literal filter subjects fails delivery | `nats-7726-mixed-filter` |
| 20 | etcd | https://github.com/etcd-io/etcd/issues/20704 | Multiple linearizability bugs in client/v3/leasing cache | `etcd-20704-leasing-linearizability` |
| 21 | hashicorp/raft | https://github.com/hashicorp/raft/issues/358 | Snapshot log compaction attempts DeleteRange with max < min | `raft-358-negative-log-range` |
| 22 | Seastar | https://github.com/scylladb/seastar/issues/2202 | Cross-shard realloc to smaller size crashes with assertion failure | `seastar-2202-cross-shard-realloc` |
| 23 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6738 | BRPOPLPUSH not woken when RPUSH happens inside Lua EVAL script | `dragonfly-6738-pipeline-block` |
| 24 | Dragonfly | https://github.com/dragonflydb/dragonfly/issues/6687 | Replica sync fails with unknown RDB encoding 62 and retries in loop | `dragonfly-6687-replica-rdb-encoding` |
| 25 | Kvrocks | https://github.com/apache/kvrocks/issues/3356 | Replication feed thread blocks on slow consumer causing WAL exhaustion | `kvrocks-3356-replication-wal` |
| 26 | Kvrocks | https://github.com/apache/kvrocks/issues/3339 | XREADGROUP BLOCK sends double response under concurrent load | `kvrocks-3339-xreadgroup-double` |
| 27 | NATS Server | https://github.com/nats-io/nats-server/issues/7718 | JetStream leaks subscriptions with overlapping stream imports and OrderedConsumer churn | `nats-7718-subscription-leak` |
| 28 | ClickHouse | https://github.com/ClickHouse/ClickHouse/issues/98079 | Keeper disconnects client after addWatch() breaking Java ZK CuratorCache | `clickhouse-98079-keeper-addwatch` |
| 29 | hashicorp/raft | https://github.com/hashicorp/raft/issues/268 | Raft.Shutdown() deadlocks with concurrent takeSnapshot() | `raft-268-shutdown-deadlock` |
| 30 | NATS Server | https://github.com/nats-io/nats-server/issues/7852 | Consumer subject filtering causes >20% performance degradation even when matching all | `nats-7852-filter-perf` |
| 31 | RocksDB | https://github.com/facebook/rocksdb/issues/10751 | Stalled writes block forever during DB::Close() shutdown | `rocksdb-10751-stalled-writes-shutdown` |
| 32 | Kvrocks | https://github.com/apache/kvrocks/issues/2520 | Namespaces not loaded into memory after full sync from master | `kvrocks-2520-namespace-fullsync` |
| 33 | Kvrocks | https://github.com/apache/kvrocks/issues/2214 | Slave misses key updates during downtime due to replication offset drift | `kvrocks-2214-slave-sync-gap` |
| 34 | hashicorp/raft | https://github.com/hashicorp/raft/issues/517 | Data race between candidate state exit and AppendEntries handler | `raft-517-candidate-appendentries-race` |
| 35 | hashicorp/raft | https://github.com/hashicorp/raft/pull/581 | Leadership transfer fails when writes advance log during transfer window | `raft-581-transfer-write-race` |
| 36 | etcd | https://github.com/etcd-io/etcd/issues/20221 | Watch on future revision receives old events after snapshot restore | `etcd-20221-watch-restore-revision` |
| 37 | NATS Server | https://github.com/nats-io/nats-server/issues/7707 | Concurrent map crash in WorkQueue consumer partition management | `nats-7707-wq-consumer-map-crash` |
