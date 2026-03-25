# Bug Reproduction Results

**Date: 2026-03-23**
**Verified reproducible from source builds: 31 cases**

Each case listed below has working `./setup.sh` and `./reproduce.sh` scripts that build from source on Ubuntu 24.04 and reliably reproduce the described bug.

To use: `cd cases/<case-name>/ && ./setup.sh && ./reproduce.sh`

The workspace location defaults to `$HOME/bug-bench/` and can be overridden with `BENCH_WORKSPACE=/your/path`.

---

## Verified Cases (31)

### Dragonfly (14)

| Case | Bug Type | Trigger |
|------|----------|---------|
| `dragonfly-6614-monitor-multiexec` | Crash (SIGABRT) | Concurrent MULTI/MONITOR/MONITOR/EXEC + connection close |
| `dragonfly-6619-evalsha-empty` | Crash (SIGABRT) | `EVALSHA "" 0` |
| `dragonfly-6654-mc-reply-large` | Crash (SIGABRT) | Memcached meta get on 16KB+ value exceeds buffer |
| `dragonfly-6687-replica-rdb-encoding` | Replication failure | Replica gets "Unknown RDB string encoding" with tiered storage master |
| `dragonfly-6738-pipeline-block` | Pipeline stall | SET+PING+BLPOP pipeline — non-blocking replies delayed by BLPOP |
| `dragonfly-6753-populate-sigfpe` | Crash (SIGFPE) | `DEBUG POPULATE 100 prefix 0` (val_size=0) |
| `dragonfly-6761-mc-pipeline-crash` | Crash (SIGABRT) | Pipelined `get nokey\r\nversion\r\n` on memcached port |
| `dragonfly-6764-hincrbyfloat-nan` | Crash (SIGABRT) | `HINCRBYFLOAT nonexist field nan` then `HRANDFIELD` |
| `dragonfly-6819-stale-expiry` | Crash (SIGABRT) | LPUSH + PEXPIRE + SORT STORE triggers stale expiry assertion |
| `dragonfly-6825-config-overflow` | Crash (SIGABRT) | DFLYCLUSTER CONFIG with `1E383` overflow value |
| `dragonfly-6856-flushslots-oob` | Crash (SIGABRT) | `DFLYCLUSTER FLUSHSLOTS 0 16384` (slot 16384 out of bounds) |
| `dragonfly-6907-ftsearch-vector-crash` | Crash (SIGABRT) | FT.CREATE HNSW index + HSET with invalid-length vector + FT.SEARCH |
| `dragonfly-6909-search-nonfinite` | Crash (SIGABRT) | `HSET doc:1 score inf` on NUMERIC-indexed field |
| `dragonfly-6912-rdb-encoding` | Crash (SIGABRT) | `DUMP` on CMS (Count-Min Sketch) key |

### NATS Server (5)

| Case | Bug Type | Trigger |
|------|----------|---------|
| `nats-7718-subscription-leak` | Resource leak | Subscription leak with overlapping stream imports |
| `nats-7726-mixed-filter` | Incorrect behavior | PWC wildcard hides literal match in subject tree intersection |
| `nats-7760-filter-stepdown` | Message delivery failure | Consumer stops matching after filter edit + leader step-down |
| `nats-7817-workqueue-message-loss` | Data loss | Messages silently removed from WorkQueue at max-deliver |
| `nats-7852-filter-perf` | Performance regression | Single FilterSubjects forces slow LoadNextMsgMulti path |

### Kvrocks (4)

| Case | Bug Type | Trigger |
|------|----------|---------|
| `kvrocks-3148-namespace-delete` | Data loss | `NAMESPACE SET ns1 token2` silently deletes ns2 |
| `kvrocks-3315-zdiff-crash` | Crash (segfault) | `ZDIFF 0 a` (numkeys=0 causes OOB) |
| `kvrocks-3339-xreadgroup-double` | Protocol violation | XREADGROUP BLOCK sends double RESP response |
| `kvrocks-3356-replication-wal` | Unbounded growth | Slow replica causes WAL to grow to 1.9GB+ |

### etcd (3)

| Case | Bug Type | Trigger |
|------|----------|---------|
| `etcd-19172-embed-data-race` | Data race | Race between `Close()` and `errHandler()` in embedded etcd |
| `etcd-20704-leasing-linearizability` | Linearizability violation | Leasing cache returns stale data after concurrent Delete+Put |
| `etcd-20893-force-new-cluster-learner` | Stale state | `--force-new-cluster` fails to remove learner members |

### Raft (2)

| Case | Bug Type | Trigger |
|------|----------|---------|
| `raft-268-shutdown-deadlock` | Deadlock | Shutdown() deadlocks with concurrent snapshot (race condition) |
| `raft-358-negative-log-range` | Invalid operation | compactLogs calls DeleteRange with from > to |

### ClickHouse (1)

| Case | Bug Type | Trigger |
|------|----------|---------|
| `clickhouse-98079-keeper-addwatch` | Protocol incompatibility | Keeper disconnects client on `addWatch` command |

### RocksDB (1)

| Case | Bug Type | Trigger |
|------|----------|---------|
| `rocksdb-10751-stalled-writes-shutdown` | Hang | `Close()` hangs when writes are stalled by rate limiter |

### Seastar (1)

| Case | Bug Type | Trigger |
|------|----------|---------|
| `seastar-2202-cross-shard-realloc` | Crash (SIGABRT) | Cross-shard realloc to smaller size triggers assertion |

---

For the full list of 29 excluded (non-reproducible) cases and their removal reasons, see `excluded_cases.md`.
