# Bug Reproduction Results

**Date: 2026-03-22**
**Attempted: 53 / 60 cases**
**Reproduced: 37 / 53 attempted (70%)**

This file logs every case that was reliably reproduced during this run, along with the method used and key observations. Cases not listed here either failed to reproduce, could not be built, or were not attempted.

---

## Successfully Reproduced Cases (37)

### Dragonfly (14 / 17)

| Case | Method | Observation |
|------|--------|-------------|
| `dragonfly-6614-monitor-multiexec` | redis-cli MULTI/MONITOR/MONITOR/EXEC + close connection | Process crashed with assertion failure (`Check failed: cc_`) on connection close after double MONITOR in MULTI/EXEC. |
| `dragonfly-6619-evalsha-empty` | redis-cli `EVALSHA "" 0` | Process crashed with `Check failed: !eval_args.sha.empty()` (SIGABRT). |
| `dragonfly-6654-mc-reply-large` | SET 8000+ byte value via Redis, retrieve via memcached meta get | Process crashed when reply exceeded `kMaxBufferSize` (8192 bytes). |
| `dragonfly-6687-replica-rdb-encoding` | Master with tiered storage + replica REPLICAOF | Replica failed with `Unknown RDB string encoding 10` during sync. Required `tiered_prefix`, `tiered_offload_threshold=1.0`, and `serialization_max_chunk_size=64000`. |
| `dragonfly-6738-pipeline-block` | Pipeline SET+PING+BLPOP in single pipeline | SET and PING replies delayed 5 seconds until BLPOP timed out, confirming pipeline flushing bug with blocking commands. |
| `dragonfly-6753-populate-sigfpe` | redis-cli `DEBUG POPULATE 100 prefix 0` | Process crashed with SIGFPE (division by zero in `DoPopulateBatch`). |
| `dragonfly-6761-mc-pipeline-crash` | `printf "get nokey\r\nversion\r\n" \| nc 127.0.0.1 11211` | Process crashed when GET was pipelined before VERSION in memcached protocol. |
| `dragonfly-6764-hincrbyfloat-nan` | `HINCRBYFLOAT nonexist field nan` then `HRANDFIELD nonexist 1` | First command creates zombie empty hash; second crashes at `hset_family.cc:973`. |
| `dragonfly-6819-stale-expiry` | `SET key val PX 500` then `SORT key STORE key` | SORT STORE overwrites key with expiry, triggering DFATAL assertion in `AddOrUpdateInternal` at `db_slice.cc`. |
| `dragonfly-6825-config-overflow` | `DFLYCLUSTER CONFIG` with slot end value `1E383` | Integer overflow causes `Check failed: rb->RepliesRecorded()` and SIGABRT. |
| `dragonfly-6856-flushslots-oob` | `DFLYCLUSTER FLUSHSLOTS 16384` | Crashed with `bitset::set: __position (16384) >= _Nb (16384)` — out-of-bounds for 0-16383 range. |
| `dragonfly-6907-ftsearch-vector-crash` | FT.CREATE with VECTOR field, HSET with wrong-sized vector, FT.SEARCH | DFATAL crash at `doc_accessors.cc:60` when search accesses malformed vector data. |
| `dragonfly-6909-search-nonfinite` | FT.CREATE with NUMERIC field, `HSET doc:1 score inf`, FT.SEARCH | Assertion failure `Check failed: std::isfinite(value)` at `range_tree.cc:84`. |
| `dragonfly-6912-rdb-encoding` | `CMS.INITBYPROB`, `CMS.INCRBY`, then `DUMP` on CMS key | Crashed with `FATAL: Unknown encoding 0 for type 17` at `rdb_save.cc:206`. |

### NATS Server (5 / 6)

| Case | Method | Observation |
|------|--------|-------------|
| `nats-7718-subscription-leak` | Go test `TestJetStreamClusterLeakedSubsWithStreamImportOverlappingJetStreamSubs` from fix commit on buggy version | Subscription counts diverge after stream/consumer create/delete cycles with overlapping account imports. |
| `nats-7726-mixed-filter` | Go test `TestGenericSublistInterestBasedIntersection/PWCDoesntHideLiteral` from fix commit on buggy version | PWC filter `one.*.six` hides literal filter `one.two.seven` — intersection returns 1 instead of 2. |
| `nats-7760-filter-stepdown` | nats CLI: edit consumer filter from `events.a` to `events.b`, step down R5 leader | `nats consumer next` times out — consumer stops matching after filter edit + leader step-down on v2.12.3. |
| `nats-7817-workqueue-message-loss` | Go test `TestJetStreamWQMaxDeliveryReached` from fix commit on v2.12.3 | `checkInterestState()` incorrectly removes messages from WorkQueue at max-deliver because `noInterest()` skips the calling consumer. |
| `nats-7852-filter-perf` | Go test `TestJetStreamConsumerSingleFilterSubjectInFilterSubjects` from fix commit on buggy version | `o.filters` is non-nil even with a single filter subject, forcing the slower `LoadNextMsgMulti` code path. |

### ClickHouse (5 / 9)

| Case | Method | Observation |
|------|--------|-------------|
| `clickhouse-29332-predicate-pushdown` | Docker v21.10, two-shard cluster, GROUP BY with WHERE IN distributed subquery | `DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED` error. Predicate pushdown rewrites the query into a double-distributed subquery. |
| `clickhouse-75699-join-merge-distributed` | Docker v25.1.3.23, JOIN on Merge table backed by Distributed table | `Code: 49. DB::Exception: Column ID UInt32 query tree node does not have valid source node`. Required exact query from the GitHub issue using `Merge(currentDatabase(), 'a')`. |
| `clickhouse-92375-distinct-distributed` | Docker v24.12, two-shard cluster with `optimize_skip_unused_shards=1` | `SELECT count() FROM (SELECT DISTINCT ...)` returns 4 instead of correct 2. |
| `clickhouse-98079-keeper-addwatch` | Docker Keeper v25.3, Java ZooKeeper client with CuratorCache | Keeper disconnects client (`KeeperErrorCode = ConnectionLoss`) after `addWatch` call. Same test passes against Apache ZooKeeper. |
| `clickhouse-99109-sum-nondeterministic` | Docker v24.12, SUM with `max_threads=1` vs `max_threads=16` | All 10 keys show different sums between single-threaded and multi-threaded execution (differences ~1e-8 to 3e-8). |

### Kvrocks (4 / 4)

| Case | Method | Observation |
|------|--------|-------------|
| `kvrocks-3148-namespace-delete` | redis-cli with auth: `NAMESPACE ADD ns1 token1`, `NAMESPACE ADD ns2 token2`, `NAMESPACE SET ns1 token2` | After NAMESPACE SET, `ns2` silently deleted. Only `ns1` and `__namespace` remain. Requires `requirepass` in config. |
| `kvrocks-3315-zdiff-crash` | redis-cli `ZDIFF 0 a` | Server crashed immediately — connection closed. Process no longer alive. |
| `kvrocks-3339-xreadgroup-double` | Raw socket test: concurrent XREADGROUP BLOCK readers on stream | Detected exact `*-1\r\n*0\r\n` double RESP response pattern (null array + empty array) in 4/5 concurrent readers. |
| `kvrocks-3356-replication-wal` | Master + replica with `iptables` 90% packet drop to replica port, 1M SET operations | Master directory grew from 4.4MB to 1.9GB (1865MB growth), far exceeding 512MB threshold. |

### etcd (3 / 7)

| Case | Method | Observation |
|------|--------|-------------|
| `etcd-19172-embed-data-race` | `go test -race -run TestEmbedEtcd ./tests/integration/embed/` (20 iterations) | Data race detected on run 3/20. Race between `Close()` at `etcd.go:460` and `errHandler()` at `etcd.go:875`. |
| `etcd-20704-leasing-linearizability` | Go test: concurrent Delete+Put with leasing cache, compare cache vs direct etcd | Leasing cache returns stale data consistently within first 1-17 iterations. Cache shows 1 KV while direct etcd returns 0 after delete. |
| `etcd-20893-force-new-cluster-learner` | 3-member cluster, add learner, trigger snapshots, stop all, `--force-new-cluster` on m1 | Member list shows 2 members (m1 + stale learner) instead of 1. Learner not cleaned up during force-new-cluster. |

### Raft (2 / 4)

| Case | Method | Observation |
|------|--------|-------------|
| `raft-268-shutdown-deadlock` | Single-node cluster with `SnapshotThreshold=1`, `SnapshotInterval=50ms`, apply entries then Shutdown() | 14/30 runs deadlocked (Shutdown blocked >15s). Circular dependency: Shutdown waits for runSnapshots, which waits for configurationsCh response from exited main loop. |
| `raft-358-negative-log-range` | Unit test: InmemStore with entries 100-200, `compactLogs(snapIdx=50)` | `DeleteRange(100, 50)` called with from > to. No bounds check in `compactLogs` when `snapIdx < firstIndex`. |

### RocksDB (1 / 2)

| Case | Method | Observation |
|------|--------|-------------|
| `rocksdb-10751-stalled-writes-shutdown` | C++ test: Open with 1KB/s rate limiter + tight L0 thresholds, write 4KB values, call Close() | `Close()` hung indefinitely — timed out after 60 seconds. Stalled writers blocked on condition variable never woken during shutdown. |

### Redpanda (2 / 3)

| Case | Method | Observation |
|------|--------|-------------|
| `redpanda-16944-raft-batcher-alloc` | Docker v24.1.1, `--smp 1`, 100 concurrent producers to single partition | 8 "oversized allocation" warnings logged, sizes doubling from 262144 (256KB) to 4194304 (4MB). Stack traces reference `raft::replicate_entries_stm::append_to_self()`. |
| `redpanda-25769-listoffsets-wrong` | Docker v24.3.7, 5 gzip-compressed records in single batch with distinct timestamps, ListOffsets query | `ListOffsets` returned offset 0 for all timestamp queries on compressed data (5/6 wrong). Uncompressed control test returned correct offsets (0 wrong). |

### Seastar (1 / 1)

| Case | Method | Observation |
|------|--------|-------------|
| `seastar-2202-cross-shard-realloc` | Built from source (parent of fix `2bc4f22b`), test: malloc 1024 on shard 0, realloc to 128 on shard 1 | Deterministic crash: `Assertion 'object_cpu_id(ptr) == cpu_id' failed` at `memory.cc:1173`. Exit code 134 (SIGABRT). Runs with `--smp 2`. |

---

## Not Reproduced (16)

| Case | Reason |
|------|--------|
| `nats-6888-stream-lost-kill9` | Non-deterministic Raft meta-stream race. 25+ kill-9/restart cycles did not trigger. |
| `etcd-20269-rejoin-panic` | Re-added node receives snapshot from leader instead of panicking. Leader's snapshot delivery prevents the problematic `tocommit` code path. |
| `etcd-20655-fast-watch` | Test from PR #20654 not in repo. Manual repro with 500 concurrent watches showed zero drops. |
| `etcd-20657-snapshot-cleanup-race` | Extremely timing-dependent. 5000 writes + leader changes on 3-node cluster did not trigger crash. |
| `etcd-20793-learner-upgrade` | Multi-version upgrade 3.5.19 -> 3.6.x completed without "too many learner" error. Scenario under-specified. |
| `cockroachdb-166122-partial-index-dataloss` | Race too rare. 5 trials with 50K rows and 500 concurrent updates each — zero NULL corruption detected. |
| `redpanda-15118-future-assert` | Non-deterministic Seastar async race. 30K+ bad-credential attempts across 4 Docker versions. No crash or exceptional future logged. |
| `clickhouse-40571-keeper-segfault` | Segfault requires multi-node Keeper cluster recovering from leader snapshot. Single-node Docker start does not trigger. |
| `clickhouse-43816-replicated-deadlock` | Timing-dependent deadlock requiring 30-60+ minutes sustained load. ~10 minutes of aggressive writes did not trigger. |
| `clickhouse-44865-merge-stuck` | Same root cause as 43816. Requires extended sustained write load. |
| `clickhouse-78074-distributed-chunk-rows` | Docker image 25.2.1.3085 appears to already contain the fix. No pre-fix image available. |
| `dragonfly-6766-json-orphans` | DCHECK at `json_family.cc:99` explicitly disabled in this version. Orphan keys created but no crash without the assertion. |
| `dragonfly-6822-expiry-cpu` | Performance regression. Server remained responsive during 600K key expiry. May require more keys or specific hardware. |
| `dragonfly-6862-dbslice-concurrent` | Race condition. 3 attempts with concurrent writes + cluster ops did not trigger crash at `db_slice.cc:550`. Setup.md also lacks specific commit. |
| `scylladb-27130-reload-segfault` | Docker startup timing differs. REST API bombardment during startup did not trigger segfault across multiple versions. |
| `scylladb-25173-truncate-raft-exit` | Docker releases use `SCYLLA_ASSERT` instead of `on_internal_error` in the truncate path — different code path. |

## Not Attempted (7)

| Case | Reason |
|------|--------|
| `raft-212-follower-snapshot-loop` | Pre-modules Go (2017). Requires Go <= 1.16 or manual GOPATH setup. |
| `raft-291-oom-verifyleader` | Pre-modules Go. Same build incompatibility. |
| `scylladb-27956-staging-sstable` | Regression in unreleased dev commit. Not in any Docker release. Requires building ScyllaDB from source (hours). |
| `scylladb-28057-ip-id-mapping` | Complex multi-node replace failure scenario. Requires ScyllaDB built from source at specific commit. |
| `scylladb-28200-uaf-streaming` | Use-after-free requires ASAN build of ScyllaDB from source. Docker images have no ASAN instrumentation. |
| `nomad-27567-scheduler-panic` | Instructions now corrected (multi-group + infeasible nodes), but not re-verified in this run. |
| `rocksdb-13652-export-cf-missing-data` | Instructions now corrected (right commit + proper export verification), but not re-verified in this run. |
