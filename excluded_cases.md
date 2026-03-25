# Excluded Cases

**Last updated: 2026-03-25**
**Total excluded: 29 cases**

This document records all bug cases confirmed as non-reproducible and removed from the benchmark suite. These cases were excluded because they could not be reliably built from source or reproduced on Ubuntu 24.04.

The benchmark suite retains only the 31 verified cases listed in `index.md` and `reproduction_results.md`.

---

## Category 1: Cannot Build from Source on Ubuntu 24.04 (6 cases)

These bugs are real (verified via Docker images) but the source code cannot be compiled on stock Ubuntu 24.04. The projects use custom internal compiler toolchains not available as packages.

| Case | Project | Issue | Bug Description | Build Failure Reason |
|------|---------|-------|-----------------|----------------------|
| `clickhouse-29332-predicate-pushdown` | ClickHouse | [#29332](https://github.com/ClickHouse/ClickHouse/issues/29332) | Predicate pushdown optimizer incorrectly rewrites distributed IN subqueries | v21.10 submodules have broken git refs |
| `clickhouse-75699-join-merge-distributed` | ClickHouse | [#75699](https://github.com/ClickHouse/ClickHouse/issues/75699) | JOIN on Merge table wrapping Distributed table crashes with LOGICAL_ERROR | Bundled magic_enum incompatible with any available Clang |
| `clickhouse-92375-distinct-distributed` | ClickHouse | [#92375](https://github.com/ClickHouse/ClickHouse/issues/92375) | SELECT DISTINCT on distributed table returns wrong results with optimize_skip_unused_shards | Same magic_enum issue as v24.12 |
| `clickhouse-99109-sum-nondeterministic` | ClickHouse | [#99109](https://github.com/ClickHouse/ClickHouse/issues/99109) | sum() on Float64 produces non-deterministic results depending on max_threads | Same magic_enum issue as v24.12 |
| `redpanda-16944-raft-batcher-alloc` | Redpanda | [#16944](https://github.com/redpanda-data/redpanda/issues/16944) | High write throughput causes oversized allocation warnings from raft replicate batcher | Seastar sub-project enforces -Werror with GCC 13-incompatible warnings |
| `redpanda-25769-listoffsets-wrong` | Redpanda | [#25769](https://github.com/redpanda-data/redpanda/issues/25769) | ListOffsets API returns wrong offsets for compressed record batches by timestamp | Same Seastar build issue |

## Category 2: Non-Deterministic / Could Not Reproduce (16 cases)

These cases build successfully but the bug could not be reliably triggered. Reasons include non-deterministic race conditions, timing-dependent failures, or environmental differences between Docker and bare metal.

| Case | Project | Issue | Bug Description | Reproduction Failure Reason |
|------|---------|-------|-----------------|----------------------------|
| `nats-6888-stream-lost-kill9` | NATS | [#6888](https://github.com/nats-io/nats-server/issues/6888) | Ungraceful kill -9 and restart loses JetStream streams | Non-deterministic Raft meta-stream race |
| `etcd-20269-rejoin-panic` | etcd | [#20269](https://github.com/etcd-io/etcd/issues/20269) | Re-added node panics with tocommit out of range | Requires snapshot from leader during rejoin; timing-dependent |
| `etcd-20655-fast-watch` | etcd | [#20655](https://github.com/etcd-io/etcd/issues/20655) | High-frequency watch creation drops events silently | Test not in repo; manual repro showed zero drops |
| `etcd-20657-snapshot-cleanup-race` | etcd | [#20657](https://github.com/etcd-io/etcd/issues/20657) | Snapshot cleanup race causes follower panic | Extremely timing-dependent; requires rapid leader changes |
| `etcd-20793-learner-upgrade` | etcd | [#20793](https://github.com/etcd-io/etcd/issues/20793) | Rolling upgrade fails with too many learner members | Multi-version upgrade completed without error in testing |
| `cockroachdb-166122-partial-index-dataloss` | CockroachDB | [#166122](https://github.com/cockroachdb/cockroach/issues/166122) | Partial index backfill with concurrent UPDATEs causes data corruption | Race too rare to trigger reliably |
| `redpanda-15118-future-assert` | Redpanda | [#15118](https://github.com/redpanda-data/redpanda/issues/15118) | Sustained auth failure load crashes with Seastar future assertion | Non-deterministic Seastar async race |
| `clickhouse-40571-keeper-segfault` | ClickHouse | [#40571](https://github.com/ClickHouse/ClickHouse/issues/40571) | Keeper crashes with segfault on every startup attempt | Requires multi-node Keeper cluster setup |
| `clickhouse-43816-replicated-deadlock` | ClickHouse | [#43816](https://github.com/ClickHouse/ClickHouse/issues/43816) | Deadlock in ReplicatedMergeTreeQueue under sustained write load | Timing-dependent; requires 30-60+ minutes sustained load |
| `clickhouse-44865-merge-stuck` | ClickHouse | [#44865](https://github.com/ClickHouse/ClickHouse/issues/44865) | Background merges permanently stop on replicas under write load | Same root cause as #43816; timing-dependent |
| `clickhouse-78074-distributed-chunk-rows` | ClickHouse | [#78074](https://github.com/ClickHouse/ClickHouse/issues/78074) | JOIN ON FALSE with Distributed + LowCardinality crashes | Docker image already contains fix |
| `dragonfly-6766-json-orphans` | Dragonfly | [#6766](https://github.com/dragonflydb/dragonfly/issues/6766) | Rapid JSON.SET/DEL cycles create orphaned objects and corrupt memory | DCHECK explicitly disabled in release builds |
| `dragonfly-6822-expiry-cpu` | Dragonfly | [#6822](https://github.com/dragonflydb/dragonfly/issues/6822) | 500k+ keys with TTL expiring simultaneously makes server unresponsive | Performance regression; not confirmed in automated test |
| `dragonfly-6862-dbslice-concurrent` | Dragonfly | [#6862](https://github.com/dragonflydb/dragonfly/issues/6862) | Concurrent writes + cluster slot migration cause crash | Race condition not triggered in 3 attempts |
| `scylladb-27130-reload-segfault` | ScyllaDB | [#27130](https://github.com/scylladb/scylla/issues/27130) | REST reload endpoint during startup crashes with segfault | Docker startup timing differs from bare metal |
| `scylladb-25173-truncate-raft-exit` | ScyllaDB | [#25173](https://github.com/scylladb/scylla/issues/25173) | Concurrent writes during DROP TABLE kill raft applier fiber | Different code path in Docker releases |

## Category 3: Not Attempted / Cannot Test (7 cases)

These cases were not attempted due to fundamental incompatibilities with the benchmark environment (pre-module Go code, requires special build flags, or requires the project built from source with custom toolchains).

| Case | Project | Issue | Bug Description | Reason Not Attempted |
|------|---------|-------|-----------------|----------------------|
| `raft-212-follower-snapshot-loop` | hashicorp/raft | [#212](https://github.com/hashicorp/raft/issues/212) | Out-of-date follower stuck in infinite snapshot install retry loop | Pre-modules Go (2017); incompatible with modern Go toolchain |
| `raft-291-oom-verifyleader` | hashicorp/raft | [#291](https://github.com/hashicorp/raft/issues/291) | Repeated VerifyLeader() with unreachable follower causes OOM | Pre-modules Go; incompatible with modern Go toolchain |
| `scylladb-27956-staging-sstable` | ScyllaDB | [#27956](https://github.com/scylladb/scylla/issues/27956) | Staging SSTables not discovered by view update generator after restart | Regression in unreleased dev commit; requires ScyllaDB built from source |
| `scylladb-28057-ip-id-mapping` | ScyllaDB | [#28057](https://github.com/scylladb/scylla/issues/28057) | Failed node replace causes IP-to-ID mapping loss | Requires ScyllaDB built from source with custom toolchain |
| `scylladb-28200-uaf-streaming` | ScyllaDB | [#28200](https://github.com/scylladb/scylla/issues/28200) | Topology changes with streaming trigger use-after-free | Requires ASAN build of ScyllaDB from source |
| `nomad-27567-scheduler-panic` | Nomad | [#27567](https://github.com/hashicorp/nomad/issues/27567) | Scheduler panics on nil pointer with system jobs and deployments | Not re-verified in latest sweep |
| `rocksdb-13652-export-cf-missing-data` | RocksDB | [#13652](https://github.com/facebook/rocksdb/issues/13652) | ExportColumnFamily occasionally misses committed data from memtable | Not re-verified in latest sweep; intermittent race |

---

## Projects Fully Removed

The following projects have zero verified cases remaining and are completely absent from the benchmark:

| Project | Language | Cases Removed | Reason |
|---------|----------|---------------|--------|
| CockroachDB | Go | 1 | Race too rare |
| Nomad | Go | 1 | Not re-verified |
| Redpanda | C++ | 2 | Cannot build (Seastar -Werror) |
| ScyllaDB | C++ | 5 | Cannot build from source / Docker-only |
