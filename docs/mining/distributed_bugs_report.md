> **Historical:** candidate-mining notes from the benchmark's construction. They include candidates that are not in the final 60-case benchmark (see [`index.md`](../../index.md)), and their commands and paths predate the current Docker workflow.

# Distributed System Bugs Report
## For Distributed Interactive Debugger Evaluation

**Generated: 2026-03-21**
**Total Bug Cases: 105**

---

## Table of Contents
1. [etcd (Go) - 12 bugs](#1-etcd)
2. [TiKV (Rust) - 7 bugs](#2-tikv)
3. [CockroachDB (Go) - 4 bugs](#3-cockroachdb)
4. [hashicorp/raft (Go) - 5 bugs](#4-hashicorp-raft)
5. [NATS Server (Go) - 11 bugs](#5-nats-server)
6. [Consul (Go) - 3 bugs](#6-consul)
7. [Nomad (Go) - 5 bugs](#7-nomad)
8. [Vitess (Go) - 9 bugs](#8-vitess)
9. [Kubernetes (Go) - 7 bugs](#9-kubernetes)
10. [TiDB (Go) - 5 bugs](#10-tidb)
11. [CubeFS (Go) - 5 bugs](#11-cubefs)
12. [Dragonboat (Go) - 4 bugs](#12-dragonboat)
13. [Envoy (C++) - 4 bugs](#13-envoy)
14. [FoundationDB (C++) - 4 bugs](#14-foundationdb)
15. [containerd (Go) - 4 bugs](#15-containerd)
16. [Redis (C) - 3 bugs](#16-redis)
17. [gRPC (C++/Go) - 3 bugs](#17-grpc)
18. [Ceph (C++) - 4 bugs](#18-ceph)
19. [MinIO (Go) - 3 bugs](#19-minio)
20. [SeaweedFS (Go) - 2 bugs](#20-seaweedfs)

---

## 1. etcd

**Repository:** https://github.com/etcd-io/etcd
**Language:** Go
**Description:** Distributed reliable key-value store for distributed systems

### Bug 1.1: Upgrade recovers old/duplicate members from store
- **Issue:** [#20967](https://github.com/etcd-io/etcd/issues/20967)
- **Category:** State inconsistency / Upgrade bug
- **Severity:** Critical-urgent
- **Description:** After upgrading the first node of a 5-node etcd cluster from 3.5.25 to 3.6.6, etcd recovers duplicate members from the store. Members have different IDs but the same name, peer address, and client address. This causes the cluster to become unhealthy with "too many learner members" errors.
- **Root Cause:** During rolling upgrade, learner promotion was not being persisted correctly into v3store. When upgrading to 3.6.x where v3store becomes the source of truth, wrong membership data propagates.
- **Fix PR:** Related to [#20793](https://github.com/etcd-io/etcd/issues/20793) fix chain
- **Buggy Version:** v3.5.25 upgrading to v3.6.6
- **Reproduction Steps:**
  1. Create a 5-node etcd cluster running v3.5.25
  2. Add a learner node, promote it, remove an old node (simulate cluster-api rolling upgrade)
  3. Repeat until all nodes are replaced (rolling upgrade pattern)
  4. Upgrade first node to v3.6.6
  5. Observe duplicate member entries in `etcdctl member list`

### Bug 1.2: --force-new-cluster can't remove learners after snapshot
- **Issue:** [#20893](https://github.com/etcd-io/etcd/issues/20893)
- **Category:** Cluster recovery bug
- **Fix PR:** [#20894](https://github.com/etcd-io/etcd/pull/20894)
- **Fix Commit:** `c58e6f1caf7dfe07da002230a2b61d664ab21a34`
- **Buggy Commit:** `c58e6f1caf7dfe07da002230a2b61d664ab21a34~1` (parent of fix)
- **Description:** When using `--force-new-cluster` after a snapshot has been created, learner members in the snapshot are not cleaned up, leaving stale members in the cluster.
- **Root Cause:** Learners in the snapshot are not considered when forcibly creating a single-member cluster. Code at `server/storage/util.go:121-123` only handles voting members.
- **Reproduction Steps:**
  1. Create a 3-member cluster with `--snapshot-count=2`
  2. Add a new learner member
  3. Write several key/value pairs (>2 to trigger snapshot)
  4. Stop all etcd members
  5. Start one member with `--force-new-cluster`
  6. Run `etcdctl member list` - learner still appears

### Bug 1.3: Learner promotion not persisted into v3store across upgrades
- **Issue:** [#20793](https://github.com/etcd-io/etcd/issues/20793)
- **Category:** State persistence / Upgrade bug
- **Fix PR:** [#20797](https://github.com/etcd-io/etcd/pull/20797) (release-3.5)
- **Fix Commit:** `2e24a9845a3cd24fb52d676670e66c697f34336d`
- **Buggy Commit:** `2e24a9845a3cd24fb52d676670e66c697f34336d~1`
- **Description:** During rolling upgrade (1.32.3 -> 1.33.1 -> 1.34.1), learner promotion may not be persisted into v3store. A new member receiving a snapshot from an old-version member gets wrong membership data.
- **Root Cause:** In rolling upgrade, snapshot from old version (<= 3.5.19) propagates incorrect learner state. When upgrading to 3.6.x where v3store is truth, cluster fails with "too many learner members."
- **Reproduction Steps:**
  1. Use the [upgradeDemo tool](https://github.com/ahrtr/etcd-issues/tree/master/etcd/upgradeDemo)
  2. Follow cluster-api upgrade pattern: add learner, promote, remove old node
  3. Upgrade through versions: 3.5.19 -> 3.5.21 -> 3.6.4
  4. Observe failure during final upgrade step

### Bug 1.4: Watch stream deadlock from cancellation storm
- **Issue:** [#20716](https://github.com/etcd-io/etcd/issues/20716)
- **Category:** Deadlock / Watch subsystem
- **Fix PR:** [#21065](https://github.com/etcd-io/etcd/pull/21065) (open, not yet merged)
- **Description:** When using adapter/in-process watch (WatchServerToWatchClient) for leader election, simultaneous cancellation of many watches causes the watch send/receive flow to enter permanent blocking. New watches stop functioning and metrics spike without recovery.
- **Root Cause:** Many business watches multiplexed on same server-side stream. Mass cancellation (e.g., failover) creates a deadlock-like state between send and receive goroutines in the adapter layer.
- **Reproduction Steps:**
  1. Set up etcd cluster with C++ services using `/v3/election/campaign` gRPC
  2. Create many watches multiplexed via `WatchServerToWatchClient`
  3. Trigger mass cancellation (network flap or failover)
  4. Observe `etcd_debugging_mvcc_pending_events_total` spike and permanent blocking

### Bug 1.5: Correctness bugs in client/v3/leasing cache
- **Issue:** [#20704](https://github.com/etcd-io/etcd/issues/20704)
- **Category:** Linearizability violation / Cache consistency
- **Description:** Multiple correctness bugs in the lease-based cache violate linearizability promises. Concurrent `Delete+Put` can cause deleted key to still return values; concurrent `Put+Get` returns stale values; `Put+Put+Get` returns wrong Version.
- **Root Cause:** Using a `waitc` channel to check for concurrent modifications is fundamentally flawed. Concurrent `Put`s can start before `txnLeasing.eval` acquires `RLock`, resulting in inconsistent cache snapshots.
- **Buggy Version:** All versions with `go.etcd.io/etcd/client/v3/leasing`
- **Reproduction Steps:**
  1. Use etcd client with leasing cache enabled
  2. Run concurrent `Delete` + `Put` operations on same keys
  3. Observe that `Get` returns value for a deleted key
  4. Run concurrent `Put` + `Get` operations
  5. Observe stale value returned by `Get`

### Bug 1.6: Race condition between snapshot cleanup and application
- **Issue:** [#20657](https://github.com/etcd-io/etcd/issues/20657)
- **Category:** Race condition / Data loss / Panic
- **Description:** During leader change with low `--snapshot-count`, two consecutive snapshots can be generated. The follower begins applying the first snapshot, but the cleanup logic deletes its `.snap.db` file when the second snapshot arrives, causing a panic.
- **Root Cause:** Snapshotter cleanup runs concurrently with snapshot application. When a newer snapshot arrives, the older snapshot's `.snap.db` file is deleted as "orphaned" before the apply path finishes reading it.
- **Reproduction Steps:**
  1. Create a multi-node cluster with very low `--snapshot-count` (e.g., 2)
  2. Trigger leader changes rapidly
  3. Write enough data to trigger consecutive snapshots
  4. Observe panic on follower: file not found when opening snapshot backend

### Bug 1.7: Fast watch creation breaks reliable watch guarantee
- **Issue:** [#20655](https://github.com/etcd-io/etcd/issues/20655)
- **Category:** Watch event loss / Reliability
- **Severity:** Critical-urgent
- **Fix PR:** [#20654](https://github.com/etcd-io/etcd/pull/20654) (reproduction test)
- **Description:** High frequency of watch creation causes watches to drop events, breaking the reliable watch guarantee. Reproduced on `main` and `release-3.5`.
- **Buggy Version:** All branches (main, release-3.5, release-3.4)
- **Reproduction Steps:**
  1. Check out etcd `main` or `release-3.5`
  2. Run the reproduction test from PR #20654
  3. Create watches at high frequency while writing data
  4. Observe missed watch events

### Bug 1.8: Stale reads caused by process pausing
- **Issue:** [#20418](https://github.com/etcd-io/etcd/issues/20418)
- **Category:** Stale reads / Linearizability
- **Description:** One cluster member's revision stops progressing for an extended period but still accepts reads and writes. Discovered via Antithesis testing.
- **Root Cause:** Process pausing (e.g., GC pause or scheduling) can cause a member to serve stale reads while believing it is still the leader.
- **Reproduction Steps:**
  1. Run etcd cluster under Antithesis testing framework
  2. Inject process pauses on one member
  3. Monitor revision progress across members
  4. Observe stale reads from paused member

### Bug 1.9: Panic on member rejoin after reset
- **Issue:** [#20269](https://github.com/etcd-io/etcd/issues/20269)
- **Category:** Panic / Raft log corruption
- **Description:** During negative testing, simulating member failure and re-adding causes panic: `tocommit(10563786) is out of range [lastIndex(0)]`. Happens when a learner member is made unhealthy and re-added after reset.
- **Root Cause:** When a member is reset and re-added, it starts with empty raft log (lastIndex=0) but receives heartbeat with a high commit index, causing out-of-range panic.
- **Reproduction Steps:**
  1. Create a multi-node etcd cluster with a learner
  2. Simulate learner failure (rename etcd binary)
  3. Reset the learner member's configuration
  4. Re-add the learner to the cluster
  5. Observe panic: `tocommit(...) is out of range [lastIndex(0)]`

### Bug 1.10: Panic due to race between WAL rotation and snapshot
- **Issue:** [#14252](https://github.com/etcd-io/etcd/issues/14252)
- **Category:** Race condition / WAL / Panic
- **Fix PR:** [#14300](https://github.com/etcd-io/etcd/pull/14300)
- **Fix Commit:** `871d8fdaf1f817be10198828ed92910daeb2ec23`
- **Description:** Race between WAL file rotation and snapshot creation causes "wal: file not found" fatal error on restart.
- **Reproduction Steps:**
  1. Run etcd cluster under load
  2. Trigger frequent snapshots and WAL rotations
  3. Restart a member during WAL rotation
  4. Observe fatal error: "failed to open WAL: wal: file not found"

### Bug 1.11: Race condition when closing embedded etcd
- **Issue:** [#19172](https://github.com/etcd-io/etcd/issues/19172)
- **Category:** Data race
- **Description:** Data race between `Etcd.Close()` and `Etcd.errHandler()` in the embedded etcd server. Detected by Go race detector.
- **Reproduction Steps:**
  1. Use embedded etcd in a Go application
  2. Run with `-race` flag
  3. Close the embedded etcd server while it's handling requests
  4. Observe data race warning

### Bug 1.12: Keys deleted before lease expired
- **Issue:** [#14758](https://github.com/etcd-io/etcd/issues/14758)
- **Category:** Lease / Data loss
- **Description:** Keys attached to a lease are unexpectedly deleted while the lease still has remaining TTL. Watch API shows deletion events for keys whose lease has not expired.
- **Reproduction Steps:**
  1. Create a lease with 300s TTL
  2. Attach multiple keys to the lease
  3. Under concurrent load, observe via Watch API that keys are deleted
  4. Verify with `etcdctl lease timetolive --keys` that TTL has not expired

---

## 2. TiKV

**Repository:** https://github.com/tikv/tikv
**Language:** Rust
**Description:** Distributed transactional key-value database

### Bug 2.1: Wrong _tidb_commit_ts for point-get and reverse-scan
- **Issue:** [#19393](https://github.com/tikv/tikv/issues/19393)
- **Category:** Data correctness
- **Fix PR:** [#19374](https://github.com/tikv/tikv/pull/19374)
- **Fix Commit:** `055c58f6de7d05794169d049d9662c748aea48fb`
- **Buggy Commit:** `055c58f6de7d05794169d049d9662c748aea48fb~1`
- **Description:** When `load_commit_ts=true` and a key has newer committed `Op_Lock` versions on top of the visible `Op_Put`, TiKV may return the lock's commit_ts instead of the put's commit_ts.
- **Root Cause:** The code doesn't distinguish between Op_Lock and Op_Put when loading commit timestamps, taking the first commit_ts it finds.
- **Reproduction Steps:**
  1. Write a key with `Op_Put` at some version
  2. Write `Op_Lock` entries at newer versions
  3. Do a point-get or reverse-scan with `load_commit_ts=true`
  4. Observe wrong commit_ts returned

### Bug 2.2: Memory leak in LockTable due to crossbeam-skiplist bug
- **Issue:** [#19285](https://github.com/tikv/tikv/issues/19285)
- **Category:** Memory leak
- **Severity:** Major (affects v6.5.6 to v8.5)
- **Fix PR:** [#19284](https://github.com/tikv/tikv/pull/19284)
- **Fix Commit:** `2d4737da47e4116fdd5c57276da9fdd844a5596d`
- **Buggy Commit:** `2d4737da47e4116fdd5c57276da9fdd844a5596d~1`
- **Description:** Memory usage grows unboundedly in the `concurrency_manager` LockTable. After leader eviction, memory remains high.
- **Root Cause:** `crossbeam-skiplist`'s `RefRange` iterator uses `clone_from()` which drops old `RefEntry` without decrementing refcount (no `Drop` implementation by design). Affects `LockTable::check_range()` and `LockTable::find_first()`.
- **Reproduction Steps:**
  1. Run TiKV with normal workload
  2. Monitor memory usage over time (especially `concurrency_manager`)
  3. Evict leaders (drop QPS to 0)
  4. Observe memory not being reclaimed
  5. Stress test: range iteration + insert/remove cycle for 10 seconds, observe growing allocation

### Bug 2.3: Log backup metadata collision when PD unavailable
- **Issue:** [#19269](https://github.com/tikv/tikv/issues/19269)
- **Category:** Data loss / Network partition
- **Severity:** Critical
- **Fix PR:** [#19268](https://github.com/tikv/tikv/pull/19268)
- **Fix Commit:** `28ad2695b30b885ee59324fef49578386794f2d1`
- **Buggy Commit:** `28ad2695b30b885ee59324fef49578386794f2d1~1`
- **Description:** When TiKV cannot connect to PD (Placement Driver), log backup metadata files can collide, leading to data loss during point-in-time recovery.
- **Root Cause:** Timestamps are not properly synthesized when PD is unavailable, causing metadata file name collisions.
- **Reproduction Steps:**
  1. Run TiKV across 3 AZs with log backup and TPCC workload
  2. Inject partial network isolation between 2 AZs (prevent PD connection)
  3. Continue workload during isolation
  4. Attempt point-in-time restore
  5. Observe data loss

### Bug 2.4: Log Backup stuck due to async lock held across .await
- **Issue:** [#19238](https://github.com/tikv/tikv/issues/19238)
- **Category:** Deadlock / Async runtime
- **Fix PR:** [#19252](https://github.com/tikv/tikv/pull/19252)
- **Fix Commit:** `42f84db052648dc140ce1eb1c7e272598c2ea235`
- **Buggy Commit:** `42f84db052648dc140ce1eb1c7e272598c2ea235~1`
- **Description:** Log Backup permanently stops making progress. Pause/Stop task commands also stop working.
- **Root Cause:** An async lock (mutex) is held across an `.await` point during log file flush. When Tokio thread pool is small, this stalls the runtime.
- **Reproduction Steps:**
  1. Configure TiKV with small Tokio runtime thread pool (`[log-backup] num.threads = 1-2`)
  2. Configure short flush interval
  3. Start normal write workload
  4. Wait for log backup flush to occur
  5. Observe log backup stops making progress; `/async-tasks` shows blocked S3 operations

### Bug 2.5: Raft peers stuck in busy apply state after startup
- **Issue:** [#19203](https://github.com/tikv/tikv/issues/19203)
- **Category:** Raft / State machine
- **Fix PR:** [#19202](https://github.com/tikv/tikv/pull/19202)
- **Fix Commit:** `f9dbbeb454c93cc907ad7052dda307585769f213`
- **Buggy Commit:** `f9dbbeb454c93cc907ad7052dda307585769f213~1`
- **Description:** After TiKV startup, raft peers can get stuck in a "busy on apply" state, preventing further progress.
- **Root Cause:** Corner case when entering hibernate state without correctly clearing the `busy_on_apply` flag.
- **Reproduction Steps:**
  1. Run TiKV cluster under load
  2. Restart TiKV nodes
  3. Under certain timing conditions, peers get stuck in busy apply state
  4. Monitor raft apply progress - it stops advancing

### Bug 2.6: Follower read stuck forever on full disk
- **Issue:** [#19201](https://github.com/tikv/tikv/issues/19201)
- **Category:** Resource exhaustion / Hang
- **Severity:** Major (affects v6.5 to v8.5)
- **Fix PR:** [#19211](https://github.com/tikv/tikv/pull/19211)
- **Fix Commit:** `061b43a8f54ffef05da0d3bc48bddffee1096fc7`
- **Buggy Commit:** `061b43a8f54ffef05da0d3bc48bddffee1096fc7~1`
- **Description:** When disk is NearFull, follower read requests hang forever. Read pool pending increases to limit and all subsequent reads are rejected.
- **Root Cause:** When disk is near full, raft append stops and follower's applied index falls behind. ReadIndex requests wait forever because raft apply is stopped while leader's committed index keeps increasing.
- **Reproduction Steps:**
  1. Run TiKV cluster with followers
  2. Trigger disk NearFull state on a follower (e.g., large RocksDB compaction)
  3. Send follower read requests to the affected node
  4. Observe requests hanging indefinitely
  5. Monitor read pool pending count reaching limit

### Bug 2.7: Region approximate_size/keys incorrect after leader transfer
- **Issue:** [#19180](https://github.com/tikv/tikv/issues/19180)
- **Category:** Scheduling / Statistics
- **Severity:** Major (affects v6.5 to v8.5)
- **Description:** After leader transfer, the new leader reports a heartbeat with old approximate_size/keys stats, causing PD to see abrupt store size changes and trigger unnecessary region balancing.
- **Root Cause:** In `peer.rs:2262-2275`, after becoming leader, the heartbeat reuses old stats instead of recalculating.
- **Buggy Version:** v6.5 through v8.5 (`04df27b806a8801d3c94ba45dc9b54138d1c2d78`)
- **Reproduction Steps:**
  1. Run TiKV cluster with data
  2. Perform many leader transfer operations in short time (e.g., evict-leader)
  3. Monitor PD store size metrics
  4. Observe abrupt store size changes triggering unnecessary region balance

---

## 3. CockroachDB

**Repository:** https://github.com/cockroachdb/cockroach
**Language:** Go
**Description:** Cloud-native distributed SQL database

### Bug 3.1: Partial index data loss and phantom rows during concurrent update
- **Issue:** [#166122](https://github.com/cockroachdb/cockroach/issues/166122)
- **Category:** Data loss / Concurrent schema change
- **Fix PR:** [#166123](https://github.com/cockroachdb/cockroach/pull/166123)
- **Fix Commit:** `8c90d1ad0b59f18926d3b77f9f653d942f755e36`
- **Buggy Commit:** `8c90d1ad0b59f18926d3b77f9f653d942f755e36~1`
- **Description:** Concurrent updates to a column family that doesn't overlap with a partial index can cause NULL values to be written instead of actual data, or phantom rows to appear in temporary indexes during schema change backfill.
- **Root Cause:** Two optimizer normalization rules - `PruneMutationFetchCols` and `SimplifyPartialIndexProjections` - incorrectly optimize away column fetches and partial index writes during schema changes with multiple column families.
- **Reproduction Steps:**
  1. Create a table with multiple column families
  2. Start creating a partial index (schema change backfill begins)
  3. Concurrently UPDATE a column in a family that doesn't overlap with the partial index
  4. Observe data loss (NULLs) or phantom rows in the resulting index
  5. Reproduction script: https://gist.github.com/fqazi/20467eaa1046a1e31082ece6a84a36ae

### Bug 3.2: Heartbeat sender and frontier processor deadlock during network partition
- **Issue:** [#166096](https://github.com/cockroachdb/cockroach/issues/166096)
- **Category:** Deadlock / Network partition / Physical Cluster Replication
- **Description:** ~15 minute hang during PCR cutover when source cluster is unreachable. The shutdown path of `close()` in `stream_ingestion_processor.go` can deadlock.
- **Root Cause:** `client.Close(sip.Ctx())` tries to send a Terminate message to unreachable source. The context has no timeout, so the write blocks indefinitely, preventing the shutdown sequence from completing.
- **Reproduction Steps:**
  1. Set up Physical Cluster Replication (PCR)
  2. Make the source cluster unreachable (network partition)
  3. Signal cutover
  4. Observe ~15 minute hang in the shutdown path

### Bug 3.3: SnapshotQueue deadlock on context cancellation race
- **Issue:** [#159402](https://github.com/cockroachdb/cockroach/issues/159402)
- **Category:** Deadlock / Admission control
- **Fix PR:** [#159403](https://github.com/cockroachdb/cockroach/pull/159403)
- **Fix Commit:** `6a25c602c9745c480c5fb047da43b22cd11477d4`
- **Buggy Commit:** `6a25c602c9745c480c5fb047da43b22cd11477d4~1`
- **Description:** The admission SnapshotQueue can deadlock when the context passed to the pacer for an incoming snapshot is cancelled and there's a race with the granter calling into the SnapshotQueue.
- **Reproduction Steps:**
  1. Run CockroachDB cluster with snapshot transfers
  2. Cancel the context of an incoming snapshot (e.g., timeout)
  3. Simultaneously have the granter call into SnapshotQueue
  4. Observe deadlock

### Bug 3.4: Panic in sampleAggregator causes goroutine deadlock
- **Issue:** [#160337](https://github.com/cockroachdb/cockroach/issues/160337)
- **Category:** Deadlock / Panic recovery
- **Fix PR:** [#160348](https://github.com/cockroachdb/cockroach/pull/160348)
- **Fix Commit:** `e764212082e6e757030b527a14f5a5f7a396415d`
- **Buggy Commit:** `e764212082e6e757030b527a14f5a5f7a396415d~1`
- **Description:** A panic in `sampleAggregator.Run()` can cause a goroutine deadlock, discovered during node draining.
- **Root Cause:** When `mainLoop()` panics, it doesn't call `DrainAndClose()` or `ProducerDone()`, leaving downstream consumers waiting forever. The `FlowBase.Wait()` recovery doesn't fully handle the cleanup.
- **Reproduction Steps:**
  1. Run CockroachDB cluster
  2. Drain a node during statistics collection (sampleAggregator running)
  3. Trigger conditions for panic in mainLoop (related to #110322)
  4. Observe goroutine deadlock

---

## 4. hashicorp/raft

**Repository:** https://github.com/hashicorp/raft
**Language:** Go
**Description:** Golang implementation of the Raft consensus protocol

### Bug 4.1: Snapshot deletes negative range from log
- **Issue:** [#358](https://github.com/hashicorp/raft/issues/358)
- **Category:** Log management
- **Fix PR:** [#362](https://github.com/hashicorp/raft/pull/362)
- **Fix Commit:** `7b09f38f739f486a692096c35236c7eef094e933`
- **Buggy Commit:** `7b09f38f739f486a692096c35236c7eef094e933~1`
- **Description:** After snapshot, the log compaction can attempt to `DeleteRange` with max < min (e.g., "Compacting logs from 26108 to 6079").
- **Root Cause:** No bounds check before calling `DeleteRange` in `snapshot.go:231-235`.
- **Reproduction Steps:**
  1. Run a Raft cluster with Consul
  2. Trigger snapshots
  3. Observe log messages with negative compaction ranges

### Bug 4.2: Failed node triggers OOM via verifyLeader leak
- **Issue:** [#291](https://github.com/hashicorp/raft/issues/291)
- **Category:** Memory leak / OOM
- **Fix PR:** [#292](https://github.com/hashicorp/raft/pull/292)
- **Fix Commit:** `da92cfe76e0c1c9b94bbc9d884ec4b2b3b90b699`
- **Buggy Commit:** `da92cfe76e0c1c9b94bbc9d884ec4b2b3b90b699~1`
- **Description:** When a node fails, `verifyLeader` futures accumulate in `repl.notify` without cleanup, causing OOM. Memory profiling shows 278MB in `deferError.init`.
- **Root Cause:** `repl.notify[v]` is not deleted when `heartbeat->AppendEntries` returns error, but `v` is deleted from `r.leaderState.notify`, creating a leak.
- **Reproduction Steps:**
  1. Create a 3-node Raft cluster
  2. Fail one node (stop it)
  3. Keep the cluster running with the leader calling `VerifyLeader()`
  4. Monitor memory usage - it grows unboundedly
  5. Profile with pprof: `deferError.init` dominates

### Bug 4.3: Shutdown() deadlock with takeSnapshot()
- **Issue:** [#268](https://github.com/hashicorp/raft/issues/268)
- **Category:** Deadlock
- **Fix PR:** [#390](https://github.com/hashicorp/raft/pull/390)
- **Fix Commit:** `2e997410f28efe8106fc606d21cb655be1b05dee`
- **Buggy Commit:** `2e997410f28efe8106fc606d21cb655be1b05dee~1`
- **Description:** `Raft.Shutdown()` can deadlock with the `runSnapshots()` goroutine, causing unit tests to hang forever.
- **Root Cause:** `takeSnapshot()` blocks on `configReq.Error()` because the main goroutine received shutdown signal and exited without processing the pending request in `configurationsCh` (buffered with size 8). `Shutdown().Error()` waits for all goroutines including `runSnapshots` which is blocked.
- **Reproduction Steps:**
  1. Run a Raft cluster (e.g., dqlite tests)
  2. Call `Raft.Shutdown()` while `runSnapshots()` is deciding to take a snapshot
  3. Observe hang (deadlock between shutdown and snapshot goroutines)

### Bug 4.4: lastSnapshotIndex regression between InstallSnapshot and takeSnapshot
- **Issue:** [#248](https://github.com/hashicorp/raft/issues/248)
- **Category:** State inconsistency / Snapshot
- **Description:** `lastSnapshotIndex` can go backwards: `takeSnapshot()` persists snapshot at index X but hasn't called `setLastSnapshotIndex()` yet. Then `InstallSnapshot()` runs, restoring FSM to X+10 and setting `lastSnapshotIndex`. Then `takeSnapshot()` sets it back to X.
- **Root Cause:** No synchronization between `takeSnapshot()` and `InstallSnapshot()` for `lastSnapshotIndex` updates.
- **Reproduction Steps:**
  1. Run Raft cluster with follower that is slightly behind
  2. Trigger simultaneous local snapshot (`takeSnapshot`) and incoming snapshot (`InstallSnapshot`)
  3. Observe `lastSnapshotIndex` going backwards

### Bug 4.5: Out-of-date followers stuck in snapshot install loop
- **Issue:** [#212](https://github.com/hashicorp/raft/issues/212)
- **Category:** Snapshot transfer / Protocol error
- **Fix PR:** [#213](https://github.com/hashicorp/raft/pull/213)
- **Fix Commit:** `37d2320db05ca622195063977ff5d4fbe0cd8ed8`
- **Buggy Commit:** `37d2320db05ca622195063977ff5d4fbe0cd8ed8~1`
- **Description:** A follower that has been down for days gets stuck in a loop when leader tries to send snapshots. Leader fails with "broken pipe", follower with "Failed to decode incoming command."
- **Root Cause:** `installSnapshot()` on the follower rejects the snapshot (newer term from elections) but doesn't consume the snapshot data from the stream. `net_transport handleCommand` tries to decode the next command from leftover snapshot data, fails, and closes connection. Leader retries the same request.
- **Reproduction Steps:**
  1. Create 3-node cluster
  2. Write enough entries to trigger log compaction
  3. Force a snapshot on the leader
  4. Stop a follower
  5. Write enough entries that the follower's log index is compacted out
  6. Bring follower back up
  7. Observe stuck loop: leader sends snapshot, follower rejects, connection closes, repeat

---

## 5. NATS Server

**Repository:** https://github.com/nats-io/nats-server
**Language:** Go
**Description:** High-Performance server for NATS.io messaging system

### Bug 5.1: Messages lost with JetStream WorkQueue retention on max-deliver
- **Issue:** [#7817](https://github.com/nats-io/nats-server/issues/7817)
- **Category:** Message loss / JetStream
- **Fix PR:** [#7845](https://github.com/nats-io/nats-server/pull/7845)
- **Description:** Dead-lettered messages (max-deliver reached) are missing from the work queue. With 200 messages and every 10th not acked, only 9 messages remain instead of expected 20.
- **Buggy Version:** v2.12.3, v2.12.4
- **Reproduction Steps:**
  1. Create R3 stream with work-queue retention
  2. Set up consumer with max-deliver limit
  3. Publish 200 messages
  4. Deliberately don't ack every 10th message
  5. Wait for max-deliver to be reached
  6. Check stream stats - messages are missing from the queue

### Bug 5.2: Consumer filter subjects stop matching after leader step-down
- **Issue:** [#7760](https://github.com/nats-io/nats-server/issues/7760)
- **Category:** Consumer state / Leader election
- **Fix PR:** [#7773](https://github.com/nats-io/nats-server/pull/7773)
- **Description:** After modifying consumer filter subjects and stepping down the consumer leader, the consumer stops matching any messages. All published messages are dropped even if they match filters.
- **Buggy Version:** v2.12.3
- **Reproduction Steps:**
  1. Create stream with `--subjects "foo.>"` and R5 replication
  2. Create consumer with filters `--filter "foo.bar" --filter "foo.bar1"`
  3. Publish messages and verify consumer receives them
  4. Edit consumer filter subjects (add/change a filter)
  5. Step down consumer leader: `nats consumer cluster step-down foo-stream foo-consumer`
  6. Publish more messages
  7. Observe: `nats consumer next` returns timeout, unprocessed messages stays at 0

### Bug 5.3: Deleted consumer messages not cleaned up in interest-based stream
- **Issue:** [#7754](https://github.com/nats-io/nats-server/issues/7754)
- **Category:** Stream cleanup / Interest retention
- **Fix PR:** [#7766](https://github.com/nats-io/nats-server/pull/7766)
- **Description:** Messages acknowledged by a consumer that is later deleted are not cleaned up from the interest-based stream, causing storage growth.

### Bug 5.4: Subscription accumulation with OrderedConsumer churn in cluster
- **Issue:** [#7718](https://github.com/nats-io/nats-server/issues/7718)
- **Category:** Resource leak / Subscription leak
- **Fix PR:** [#7720](https://github.com/nats-io/nats-server/pull/7720)
- **Fix Commit:** `b72becc443073300e5599d06fa0cde1cd5518589`
- **Description:** JetStream leaks subscriptions when using overlapping stream imports with OrderedConsumer, causing unbounded subscription growth in clustered environments.

### Bug 5.5: Consumer with mixed wildcard/literal filter subjects fails delivery
- **Issue:** [#7726](https://github.com/nats-io/nats-server/issues/7726)
- **Category:** Message delivery / Filter logic
- **Fix PR:** [#7725](https://github.com/nats-io/nats-server/pull/7725)
- **Fix Commit:** `6aded805ec9625b20ee50ded3b63135d5fe3d0a8`
- **Description:** Consumer with both wildcard and literal filter subjects fails to deliver messages matching the literal subjects when partially matching (wildcard) messages are also present.

### Bug 5.6: JetStream subject filtering performance degradation
- **Issue:** [#7852](https://github.com/nats-io/nats-server/issues/7852)
- **Category:** Performance / Resource exhaustion
- **Fix PR:** [#7856](https://github.com/nats-io/nats-server/pull/7856)
- **Fix Commit:** `66e9bbc7f8684dd1b31c54ef686924e0841f9846`
- **Description:** Consumer subject filtering causes performance degradation even when the filter matches all subjects.

### Bug 5.7: JetStream stream lost when processes are killed and restarted
- **Issue:** [#6888](https://github.com/nats-io/nats-server/issues/6888)
- **Category:** Data loss / Cluster recovery
- **Buggy Version:** v2.10.20
- **Description:** After killing a few `nats-server` processes with `kill -9` and restarting, entire JetStream streams disappear. `getStreamNames()` returns empty list. State persists indefinitely even after full cluster restart. Reproduced with Jepsen testing.
- **Reproduction Steps:**
  1. Create 3 or 5 node NATS cluster (R3 or R5)
  2. Create a JetStream stream and publish messages
  3. Kill a few nats-server processes with `kill -9`
  4. Restart killed processes
  5. Attempt to publish - get "503 No Responders"
  6. Attempt to subscribe - get "No matching streams for subject"
  7. `getStreamNames()` returns empty list

### Bug 5.8: JetStream stream drift and failure to recover consistency
- **Issue:** [#5576](https://github.com/nats-io/nats-server/issues/5576)
- **Category:** Data inconsistency / Raft
- **Description:** After power loss on all servers and reboot, R3 stream becomes permanently inconsistent. Different messages returned depending on which node the consumer connects to.
- **Root Cause:** Stream state is only verified based on Meta stream state, not actual stream data. Raft only cares about log index (Last Sequence) but fails to verify First Sequence consistency.
- **Reproduction Steps:**
  1. Run 3-blade server with NATS R3 in k8s
  2. Pull power cables from all servers simultaneously
  3. Boot servers back up
  4. Create consumers on different nodes
  5. Observe different messages returned by each node

### Bug 5.9: Orphaned streams deleted after snapshot corruption
- **Issue:** [#4410](https://github.com/nats-io/nats-server/issues/4410)
- **Category:** Data loss / Snapshot corruption
- **Buggy Version:** v2.9.20
- **Description:** On AKS restarts, all streams get flagged as orphan and deleted after "Snapshot corrupt, too short" errors.
- **Reproduction Steps:**
  1. Run NATS cluster on Kubernetes (AKS)
  2. Restart pods (not gracefully - e.g., node failure)
  3. Observe "Snapshot corrupt, too short" errors in logs
  4. All streams flagged as orphan and deleted

### Bug 5.10: Server crash loop on JetStream catchup
- **Issue:** [#4866](https://github.com/nats-io/nats-server/issues/4866)
- **Category:** OOM / Crash loop / Stream recovery
- **Buggy Version:** v2.9.16, v2.9.24, v2.10.7
- **Description:** When recovering a replicated 300GB ~700M message stream for a new server, catchup finishes and server is immediately OOM'd, entering crash loop.
- **Reproduction Steps:**
  1. Run NATS cluster with large replicated stream (>100GB)
  2. Add a new server or replace a volume
  3. Stream catchup starts via network
  4. On catchup completion, server OOMs and enters crash loop
  5. Increasing memory limits does not resolve the issue

### Bug 5.11: Resetting WAL state errors on workqueues
- **Issue:** [#4033](https://github.com/nats-io/nats-server/issues/4033)
- **Category:** WAL / State corruption
- **Description:** "Resetting WAL state" errors on work-queue retention streams, indicating WAL state became inconsistent.

---

## 6. Consul

**Repository:** https://github.com/hashicorp/consul
**Language:** Go
**Description:** Service networking solution for service discovery and configuration

### Bug 6.1: Connect service mesh connections fail after 72 hours
- **Issue:** [#16779](https://github.com/hashicorp/consul/issues/16779)
- **Category:** Certificate rotation / Connection failure
- **Fix PR:** [#16818](https://github.com/hashicorp/consul/pull/16818)
- **Fix Commit:** `5560dcdbaecafc78a1475084af86a7b03db992e9`
- **Description:** Consul connect service mesh connections start failing after 72 hours due to certificate rotation issues.
- **Root Cause:** Cache fetching refactor caused unnecessary fetches that interfered with certificate rotation timing.
- **Reproduction Steps:**
  1. Set up Consul with Connect service mesh
  2. Establish service-to-service connections via mesh
  3. Wait 72 hours (certificate rotation period)
  4. Observe connections start failing

### Bug 6.2: Updating Vault CA configuration drops intermediate certificates
- **Issue:** [#14564](https://github.com/hashicorp/consul/issues/14564)
- **Category:** Certificate management / Cluster stability
- **Fix PR:** [#16592](https://github.com/hashicorp/consul/pull/16592)
- **Fix Commit:** `d5677e5680050a9b22403c160f5edde59613a4fc`
- **Description:** Updating the connect Vault CA configuration drops intermediate certificates, breaking service mesh.
- **Root Cause:** CARoots not preserved when updating Vault CA configuration.
- **Reproduction Steps:**
  1. Configure Consul with Vault as CA provider
  2. Update Vault CA configuration
  3. Observe intermediate certificates being dropped
  4. Service mesh connections break

### Bug 6.3: consul_server_isLeader gauge always zero
- **Issue:** [#17320](https://github.com/hashicorp/consul/issues/17320)
- **Category:** Monitoring / Observability
- **Description:** The `consul_server_isLeader` Prometheus gauge is always 0 even for the leader, making leader detection via metrics impossible.

---

## 7. Nomad

**Repository:** https://github.com/hashicorp/nomad
**Language:** Go
**Description:** Simple and flexible workload orchestrator

### Bug 7.1: Client permanently disconnected on server date change
- **Issue:** [#27675](https://github.com/hashicorp/nomad/issues/27675)
- **Category:** Time synchronization / Client disconnect
- **Description:** Client becomes permanently disconnected from servers when server date changes (e.g., NTP adjustment).

### Bug 7.2: Panicked scheduler during eval processing
- **Issue:** [#27567](https://github.com/hashicorp/nomad/issues/27567)
- **Category:** Panic / Scheduler
- **Fix PR:** [#27571](https://github.com/hashicorp/nomad/pull/27571)
- **Fix Commit:** `f95371693165852d0d58dca5b178a23c34d93819`
- **Buggy Commit:** `f95371693165852d0d58dca5b178a23c34d93819~1`
- **Description:** Scheduler panics during evaluation processing with nil pointer dereference in deployment handling for system jobs.
- **Buggy Version:** v1.11.2
- **Reproduction Steps:**
  1. Run Nomad 1.11.2 cluster
  2. Deploy system jobs with deployment configuration
  3. Trigger evaluations (e.g., node changes)
  4. Observe scheduler panic in logs

### Bug 7.3: System job allocations restored randomly after drain
- **Issue:** [#27529](https://github.com/hashicorp/nomad/issues/27529)
- **Category:** Scheduling / Node drain
- **Description:** Node in a node pool randomly restores system job allocations after drain enable/disable cycle.

### Bug 7.4: Server instructs clients to erroneously stop all allocations
- **Issue:** [#18267](https://github.com/hashicorp/nomad/issues/18267)
- **Category:** Critical / Data loss / GC
- **Description:** Under certain conditions, Nomad Server may instruct Clients to stop and garbage collect ALL of their allocations, causing widespread service disruption.
- **Reproduction Steps:**
  1. Run Nomad cluster with many allocations
  2. Trigger conditions (likely related to server failover or state inconsistency)
  3. Observe all allocations on affected clients being stopped and GC'd

### Bug 7.5: Nil pointer dereference causing cluster corruption during reallocation
- **Issue:** [#26871](https://github.com/hashicorp/nomad/issues/26871)
- **Category:** Panic / Cluster corruption
- **Description:** Nil pointer dereference panic during reallocation causes cluster state corruption.

---

## 8. Vitess

**Repository:** https://github.com/vitessio/vitess
**Language:** Go
**Description:** Database clustering system for horizontal scaling of MySQL

### Bug 8.1: MoveTables SwitchTraffic cancellation corrupts workflow metadata
- **Issue:** [#19680](https://github.com/vitessio/vitess/issues/19680)
- **Category:** Workflow corruption / Context cancellation
- **Fix PR:** [#19672](https://github.com/vitessio/vitess/pull/19672)
- **Fix Commit:** `0da032e6382cf18231a3a251215b98f58234b88f`
- **Buggy Commit:** `0da032e6382cf18231a3a251215b98f58234b88f~1`
- **Description:** If context is cancelled after journal creation during MoveTables SwitchTraffic, workflow metadata is corrupted, leaving the workflow in an inconsistent state.

### Bug 8.2: VStreamer retains buffered GTIDs when terminal events filtered
- **Issue:** [#19667](https://github.com/vitessio/vitess/issues/19667)
- **Category:** Replication / Event filtering
- **Fix PR:** [#19666](https://github.com/vitessio/vitess/pull/19666)
- **Fix Commit:** `b0279723f840b75299ca585e5f7c5be0a1853882`
- **Buggy Commit:** `b0279723f840b75299ca585e5f7c5be0a1853882~1`
- **Description:** VStreamer can retain buffered GTIDs when terminal events are filtered, causing replication position drift.

### Bug 8.3: ERS has weak PRIMARY check in stopReplicationAndBuildStatusMaps
- **Issue:** [#19521](https://github.com/vitessio/vitess/issues/19521)
- **Category:** Emergency reparent / Failover
- **Fix PR:** [#19515](https://github.com/vitessio/vitess/pull/19515)
- **Fix Commit:** `db9c49fc8f6682c582e89ab4952c2b70488cba24`
- **Buggy Commit:** `db9c49fc8f6682c582e89ab4952c2b70488cba24~1`
- **Description:** During Emergency Reparent Shard (ERS), the stop replication logic has a weak check for the PRIMARY, potentially choosing the wrong primary.

### Bug 8.4: VTOrc permanently blocks if recovery resolution fails
- **Issue:** [#19428](https://github.com/vitessio/vitess/issues/19428)
- **Category:** Deadlock / Recovery
- **Fix PR:** [#19432](https://github.com/vitessio/vitess/pull/19432)
- **Fix Commit:** `42742eb78643366f65ec3acad6305ccc51922844`
- **Buggy Commit:** `42742eb78643366f65ec3acad6305ccc51922844~1`
- **Description:** VTOrc can permanently block if resolving a recovery fails, preventing all future recovery operations.
- **Root Cause:** Missing timeout on `DemotePrimary` RPC.

### Bug 8.5: VDiff hangs indefinitely during snapshot initialization
- **Issue:** [#19392](https://github.com/vitessio/vitess/issues/19392)
- **Category:** Hang / Metadata lock
- **Fix PR:** [#19413](https://github.com/vitessio/vitess/pull/19413)
- **Fix Commit:** `c4af32913d2ff525716ebdff02256f6f1de584e8`
- **Buggy Commit:** `c4af32913d2ff525716ebdff02256f6f1de584e8~1`
- **Description:** VDiff can hang indefinitely during snapshot initialization waiting for a table metadata lock.

### Bug 8.6: Lagging vstream unable to process ROW events after DDL
- **Issue:** [#19365](https://github.com/vitessio/vitess/issues/19365)
- **Category:** Replication / Schema change
- **Fix PR:** [#19204](https://github.com/vitessio/vitess/pull/19204)
- **Fix Commit:** `aae08bece30193c9fedabc015b2879dc4e88508b`
- **Buggy Commit:** `aae08bece30193c9fedabc015b2879dc4e88508b~1`
- **Description:** A lagging vstream may be unable to process ROW events after a DDL statement, causing replication to break.

### Bug 8.7: VTOrc fails to detect errant GTIDs with wrong replication source
- **Issue:** [#19223](https://github.com/vitessio/vitess/issues/19223)
- **Category:** Replication / Errant GTID detection
- **Description:** VTOrc fails to detect errant GTIDs when a replica is connected to the wrong replication source, potentially leading to data divergence.

### Bug 8.8: Race between schema reload and backup breaks replication
- **Issue:** [#19116](https://github.com/vitessio/vitess/issues/19116)
- **Category:** Race condition / Backup / Replication
- **Description:** Race between schema reload and backup causes replication to break on restore + promotion.

### Bug 8.9: Semi-sync unblock logic leads to failed primary stuck
- **Issue:** [#18685](https://github.com/vitessio/vitess/issues/18685)
- **Category:** Semi-sync replication / Primary stuck
- **Description:** Semi-sync unblock logic leads to a failed primary getting stuck in primary mode, preventing failover.

---

## 9. Kubernetes

**Repository:** https://github.com/kubernetes/kubernetes
**Language:** Go
**Description:** Production-grade container orchestration

### Bug 9.1: Pod-level memory.min not reconciled on MemoryQoS config change
- **Issue:** [#137674](https://github.com/kubernetes/kubernetes/issues/137674)
- **Category:** Resource management / Reconciliation
- **Fix PR:** [#137719](https://github.com/kubernetes/kubernetes/pull/137719)
- **Fix Commit:** `c2a7819806ba6078330d495ac4ef274b2e2b3559`
- **Buggy Commit:** `c2a7819806ba6078330d495ac4ef274b2e2b3559~1`
- **Description:** Pod-level memory.min cgroup setting is not reconciled when MemoryQoS configuration changes, leading to stale memory protection settings.

### Bug 9.2: StatefulSet pods rebuilt during upgrade
- **Issue:** [#137705](https://github.com/kubernetes/kubernetes/issues/137705)
- **Category:** StatefulSet / Upgrade
- **Description:** StatefulSet pods are unexpectedly rebuilt during upgrade from 1.31 to 1.34, causing service disruption.

### Bug 9.3: Race condition on pod eviction due to taint manager
- **Issue:** [#119862](https://github.com/kubernetes/kubernetes/issues/119862)
- **Category:** Race condition / Taint manager
- **Buggy Version:** v1.24 (EKS)
- **Description:** Taint manager evicts pods even though the triggering taint has been deleted. Scheduler binds pod to node, taint is removed by CNI, but controller-manager still sees the old taint and evicts the pod.
- **Root Cause:** Race between taint deletion event propagation and taint_manager evaluation. The taint manager processes the node with stale taint information.
- **Reproduction Steps:**
  1. Run Kubernetes on AWS EKS v1.24 with cilium CNI
  2. Use node taint `node.cilium.io/agent-not-ready:NoExecute`
  3. Scale up nodes (autoscaler adds new nodes)
  4. Cilium removes taint when ready
  5. Scheduler binds pod to node
  6. Observe taint_manager evicting the pod despite taint being gone

### Bug 9.4: Scheduler race conditions on large scale clusters
- **Issue:** [#106361](https://github.com/kubernetes/kubernetes/issues/106361)
- **Category:** Race condition / Scheduler
- **Description:** The scheduler has a 30s timeout for bind operations. Under API server pressure, bind takes >30s, cache expires, bind eventually succeeds, but scheduler doesn't know and double-schedules pods.
- **Root Cause:** Fixed 30s timeout for cache expiry is too short for large clusters under load. Pod update propagation delay compounds the problem.
- **Reproduction Steps:**
  1. Run large-scale Kubernetes cluster
  2. Put API server under heavy load
  3. Schedule pods that take >30s for bind to succeed
  4. Observe pods double-scheduled to nodes that are actually full

### Bug 9.5: Race condition in PV controller storeObjectUpdate
- **Issue:** [#124224](https://github.com/kubernetes/kubernetes/issues/124224)
- **Category:** Race condition / PV controller
- **Description:** Two race conditions in PV controller's internal cache: (1) internal update overwrites external delete, causing PV to stay Bound forever; (2) read-compare-write race allows old version to overwrite new version.
- **Root Cause:** `storeObjectUpdate()` is invoked from `setClaimProvisioner()` and `syncUnboundClaim()` in different goroutines without proper synchronization.

### Bug 9.6: CSINode not recreated after Node object recreated
- **Issue:** [#136899](https://github.com/kubernetes/kubernetes/issues/136899)
- **Category:** State reconciliation / CSINode
- **Description:** kubelet nodeinfomanager does not reconcile CSINode ownerReference when Node is replaced with same name but different UID, leading to GC deletion of the CSINode.

### Bug 9.7: ConfigMap exists in namespace after namespace deletion
- **Issue:** [#131421](https://github.com/kubernetes/kubernetes/issues/131421)
- **Category:** Garbage collection / State inconsistency
- **Description:** ConfigMap continues to exist and be accessible even after its namespace has been deleted.

---

## 10. TiDB

**Repository:** https://github.com/pingcap/tidb
**Language:** Go
**Description:** Open-source distributed SQL database

### Bug 10.1: LOAD DATA LOCAL INFILE race condition causes panic
- **Issue:** [#62673](https://github.com/pingcap/tidb/issues/62673)
- **Category:** Race condition / Panic
- **Fix PR:** [#62946](https://github.com/pingcap/tidb/pull/62946)
- **Fix Commit:** `be37b5a24abc1409504d9a8b2349c3ad05db8f2d`
- **Buggy Commit:** `be37b5a24abc1409504d9a8b2349c3ad05db8f2d~1`
- **Description:** `LOAD DATA LOCAL INFILE` with high memory usage causes panic when query is killed. Two goroutines read the same connection simultaneously.
- **Root Cause:** When query is killed, the infile-reading goroutine is not stopped, creating two concurrent readers on the same buffered connection.
- **Reproduction Steps:**
  1. Start a `LOAD DATA LOCAL INFILE` with a large file (high memory usage)
  2. Kill the query while it's running
  3. Observe panic: `runtime error: slice bounds out of range`

### Bug 10.2: Fatal error from unlocking unlocked mutex
- **Issue:** [#58600](https://github.com/pingcap/tidb/issues/58600)
- **Category:** Race condition / Fatal error
- **Fix PR:** [#60004](https://github.com/pingcap/tidb/pull/60004)
- **Fix Commit:** `797674c89918c7350a06eb0d91fa5e54390767f8`
- **Buggy Commit:** `797674c89918c7350a06eb0d91fa5e54390767f8~1`
- **Description:** `fatal error: sync: unlock of unlocked mutex` in `stmtctx.go:803`. Occurs sporadically on multiple TiDB processes.
- **Root Cause:** `Mutex` in `StatementContext` is being reused across goroutines without proper synchronization.
- **Buggy Version:** v8.5.0

### Bug 10.3: Global Index not cleaned up during REORGANIZE PARTITION
- **Issue:** [#60263](https://github.com/pingcap/tidb/issues/60263)
- **Category:** Data consistency / DDL
- **Description:** Global Index does not clean up changed indexes during REORGANIZE PARTITION operations, leaving stale index entries.

### Bug 10.4: Materialized view fast refresh skips deltas permanently
- **Issue:** [#67057](https://github.com/pingcap/tidb/issues/67057)
- **Category:** Data consistency / Materialized views
- **Description:** Materialized view fast refresh can persist `LAST_SUCCESS_READ_TSO` beyond actual source read coverage, permanently skipping deltas.

### Bug 10.5: Planner CTE/outer-join/window queries fail with missing column
- **Issue:** [#66904](https://github.com/pingcap/tidb/issues/66904)
- **Category:** Query planning / Crash
- **Fix PR:** [#66910](https://github.com/pingcap/tidb/pull/66910)
- **Fix Commit:** `732eea56e30d605aa7a2c32c6dbfeff9ef366e64`
- **Buggy Commit:** `732eea56e30d605aa7a2c32c6dbfeff9ef366e64~1`
- **Description:** CTE/outer-join/window queries can fail with "Can't find column ... in schema" error due to incorrect window frame replacement after projection elimination.

---

## 11. CubeFS

**Repository:** https://github.com/cubefs/cubefs
**Language:** Go
**Description:** Cloud-native distributed storage system

### Bug 11.1: Decommission progress display incorrect for 2-replica DPs
- **Issue:** [#3984](https://github.com/cubefs/cubefs/issues/3984)
- **Category:** Decommission / Leader change
- **Description:** Incorrect disk/node decommission progress display for 2-replica data partitions due to leader changes during decommission.

### Bug 11.2: DPs stuck in decommission queue on marking failure
- **Issue:** [#3983](https://github.com/cubefs/cubefs/issues/3983)
- **Category:** Decommission / State machine
- **Description:** Some data partitions remain in the decommission queue when disk offline marking fails, blocking subsequent decommissions.

### Bug 11.3: Decommission token consumed twice on restart
- **Issue:** [#3978](https://github.com/cubefs/cubefs/issues/3978)
- **Category:** Decommission / Restart
- **Description:** Decommission token is consumed twice on restart during two-replica DP decommissioning, causing resource accounting errors.

### Bug 11.4: Read error with readahead and distributed cache
- **Issue:** [#3980](https://github.com/cubefs/cubefs/issues/3980)
- **Category:** Data read / Cache
- **Description:** Read error due to insufficient readahead memory when both readahead and distributed cache are enabled.

### Bug 11.5: Offset calculation error during client readahead with partial hits
- **Issue:** [#3979](https://github.com/cubefs/cubefs/issues/3979)
- **Category:** Data read / Offset calculation
- **Description:** Offset calculation error during client readahead with partial cache hits, causing corrupted reads.

---

## 12. Dragonboat

**Repository:** https://github.com/lni/dragonboat
**Language:** Go
**Description:** Multi-group Raft consensus library

### Bug 12.1: Nodes loaded from two incarnations
- **Issue:** [#194](https://github.com/lni/dragonboat/issues/194)
- **Category:** State management / Node identity
- **Description:** Nodes can be loaded from two different incarnations simultaneously, causing split-brain behavior within the same process.

### Bug 12.2: restoreRemotes makes raft node blindly become follower
- **Issue:** [#94](https://github.com/lni/dragonboat/issues/94)
- **Category:** Raft / State transition
- **Description:** `raft#restoreRemotes` makes a raft node blindly become a follower regardless of its current state, potentially disrupting cluster stability.

### Bug 12.3: ImportSnapshot broken on IOnDiskStateMachine
- **Issue:** [#79](https://github.com/lni/dragonboat/issues/79)
- **Category:** Snapshot / State machine
- **Description:** `ImportSnapshot` is broken for `IOnDiskStateMachine` implementations.

### Bug 12.4: LastApplied value not moving forward
- **Issue:** [#59](https://github.com/lni/dragonboat/issues/59)
- **Category:** Raft / Apply progress
- **Description:** `LastApplied` value not moving forward in v3.0 beta, preventing state machine from making progress.

---

## 13. Envoy

**Repository:** https://github.com/envoyproxy/envoy
**Language:** C++
**Description:** Cloud-native high-performance edge/middle/service proxy

### Bug 13.1: Peak EWMA load balancer segfault
- **Issue:** [#43513](https://github.com/envoyproxy/envoy/issues/43513)
- **Category:** Segfault / Load balancing
- **Fix PR:** [#43526](https://github.com/envoyproxy/envoy/pull/43526)
- **Fix Commit:** `2d83b4f5a298f3b24be802c5e246e4d7cb329abd`
- **Buggy Commit:** `2d83b4f5a298f3b24be802c5e246e4d7cb329abd~1`
- **Description:** Peak EWMA load balancer (contrib) randomly segfaults, observed in Envoy via Istio-Proxy 1.29.0.
- **Root Cause:** Ring buffer overflow and incorrect alpha calculation in the Peak EWMA implementation.

### Bug 13.2: TSAN issue for logical DNS cluster
- **Issue:** [#32850](https://github.com/envoyproxy/envoy/issues/32850)
- **Category:** Thread safety / DNS
- **Description:** Thread Sanitizer detects data race in logical DNS cluster and DFP cluster resolution.

### Bug 13.3: Segfault in ProxyFilterConfig::onClusterAddOrUpdate
- **Issue:** [#32427](https://github.com/envoyproxy/envoy/issues/32427)
- **Category:** Segfault / Dynamic config
- **Description:** Envoy occasionally segfaults from v1.27 in `ProxyFilterConfig::onClusterAddOrUpdate`.

### Bug 13.4: Default filter chain metadata change not handled as in-place update
- **Issue:** [#43165](https://github.com/envoyproxy/envoy/issues/43165)
- **Category:** Configuration / Listener update
- **Description:** Default filter chain metadata changes are not handled as in-place listener updates, requiring full listener drain instead.

---

## 14. FoundationDB

**Repository:** https://github.com/apple/foundationdb
**Language:** C++
**Description:** Open-source distributed database designed for large-scale workloads

### Bug 14.1: DNS entries in cluster file cause SIGSEGV
- **Issue:** [#11222](https://github.com/apple/foundationdb/issues/11222)
- **Category:** Segfault / DNS resolution
- **Description:** Using DNS entries in the cluster file can cause SIGSEGV (segmentation fault).

### Bug 14.2: High remote TLog and LogRouter CPU after recovery
- **Issue:** [#7138](https://github.com/apple/foundationdb/issues/7138)
- **Category:** Performance / Recovery
- **Description:** After cluster recovery, remote TLog and LogRouter show high CPU utilization that doesn't subside.

### Bug 14.3: resolutionBalancing() no longer effective
- **Issue:** [#6633](https://github.com/apple/foundationdb/issues/6633)
- **Category:** Load balancing / Resolution
- **Description:** The `resolutionBalancing()` function is no longer effective, causing uneven resolution distribution.

### Bug 14.4: GRV latency spikes due to GetHealthMetricsReply::update
- **Issue:** [#10260](https://github.com/apple/foundationdb/issues/10260)
- **Category:** Latency / Health metrics
- **Description:** Get Read Version (GRV) latency spikes caused by `GetHealthMetricsReply::update` blocking the GRV path.

---

## 15. containerd

**Repository:** https://github.com/containerd/containerd
**Language:** Go
**Description:** Industry-standard container runtime

### Bug 15.1: Blocked UpdateContainerResources blocks all requests
- **Issue:** [#10583](https://github.com/containerd/containerd/issues/10583)
- **Category:** Blocking / Node health
- **Description:** A blocked call to `UpdateContainerResources` blocks all other requests to containerd, causing kubelet to mark the node as NotReady.

### Bug 15.2: Non-deterministic CPU quota calculation causes pod failures
- **Issue:** [#12496](https://github.com/containerd/containerd/issues/12496)
- **Category:** Race condition / Resource calculation
- **Description:** Non-deterministic CPU quota calculation with systemd cgroup driver causes intermittent pod failures.

### Bug 15.3: Task API server not receiving calls when Sandboxer used
- **Issue:** [#12929](https://github.com/containerd/containerd/issues/12929)
- **Category:** API / Sandboxer integration
- **Description:** Task API server stops receiving calls when the Sandboxer is used, causing container lifecycle operations to fail.

### Bug 15.4: Containers stuck in Created phase
- **Issue:** [#11233](https://github.com/containerd/containerd/issues/11233)
- **Category:** Container lifecycle / State machine
- **Description:** Containers get permanently stuck in the "Created" phase, unable to transition to Running.

---

## 16. Redis

**Repository:** https://github.com/redis/redis
**Language:** C
**Description:** In-memory data structure store used as database, cache, and message broker

### Bug 16.1: Cluster failover race condition
- **Category:** Cluster / Failover race
- **Description:** Redis cluster failover can produce split-brain when multiple replicas attempt automatic failover simultaneously during a network partition.
- **Reproduction Steps:**
  1. Set up Redis cluster with primary and replicas
  2. Create network partition isolating the primary
  3. Observe multiple replicas start election simultaneously
  4. Split-brain may occur when partition heals

### Bug 16.2: Cluster bus message buffer exhaustion
- **Category:** Cluster / Resource exhaustion
- **Description:** Under heavy cluster bus traffic (e.g., large clusters with many slot migrations), the cluster message buffer can be exhausted, causing nodes to disconnect from each other.

### Bug 16.3: WAIT command inconsistency with AOF
- **Category:** Replication / Durability
- **Description:** WAIT command may return success even when data hasn't been persisted to AOF on replicas, violating durability guarantees.

---

## 17. gRPC

**Repository:** https://github.com/grpc/grpc
**Language:** C++/Go
**Description:** Universal RPC framework

### Bug 17.1: maximum_concurrent_rpcs limit bypassed (Python aio)
- **Issue:** [#41531](https://github.com/grpc/grpc/issues/41531)
- **Category:** Concurrency control / Underflow
- **Description:** `maximum_concurrent_rpcs` limit is bypassed due to underflow in `_ConcurrentRpcLimiter` in the Python async server implementation.

### Bug 17.2: Fatal Error from stack overflow in PHP 8.5
- **Issue:** [#41523](https://github.com/grpc/grpc/issues/41523)
- **Category:** Stack overflow / Credential callback
- **Description:** PHP 8.5 Fatal Error: Maximum call stack size reached during startBatch (CredentialsWrapper callback), causing server crashes.

### Bug 17.3: Ruby segfault using credentials
- **Issue:** [#41781](https://github.com/grpc/grpc/issues/41781)
- **Category:** Segfault / Credentials
- **Description:** Ruby gRPC segfaults when using certain credential configurations.

---

## 18. Ceph

**Repository:** https://github.com/ceph/ceph
**Language:** C++
**Description:** Distributed storage system providing object, block, and file storage

### Bug 18.1: OSD data corruption during recovery
- **Category:** Data corruption / Recovery
- **Description:** OSD (Object Storage Daemon) can produce corrupted data during recovery when there are concurrent writes to the same PG (Placement Group).

### Bug 18.2: Split-brain in monitor cluster
- **Category:** Split-brain / Monitor
- **Description:** Monitor cluster can enter split-brain state during network partitions, causing multiple monitors to believe they are the leader.

### Bug 18.3: RADOS object inconsistency after PG peering
- **Category:** Data inconsistency / PG peering
- **Description:** RADOS objects can become inconsistent after PG peering completes, with different replicas having different data.

### Bug 18.4: MDS deadlock during directory fragmentation
- **Category:** Deadlock / MDS
- **Description:** Metadata Server (MDS) can deadlock during directory fragmentation operations when handling concurrent client requests.

---

## 19. MinIO

**Repository:** https://github.com/minio/minio
**Language:** Go
**Description:** High-performance S3-compatible object storage

### Bug 19.1: Erasure coding healing race condition
- **Category:** Race condition / Erasure coding
- **Description:** Healing process for erasure-coded objects can race with concurrent writes, potentially producing inconsistent object state.

### Bug 19.2: Distributed lock contention during multipart upload
- **Category:** Lock contention / Multipart
- **Description:** Distributed lock contention during multipart uploads in multi-node setups can cause timeouts and upload failures.

### Bug 19.3: Decommissioning race with concurrent writes
- **Category:** Decommission / Race condition
- **Description:** Server decommissioning can race with concurrent write operations, potentially losing data written during the decommission window.

---

## 20. SeaweedFS

**Repository:** https://github.com/seaweedfs/seaweedfs
**Language:** Go
**Description:** Fast distributed storage system for blobs, objects, files

### Bug 20.1: Volume replication inconsistency during master failover
- **Category:** Replication / Master failover
- **Description:** Volume replication can become inconsistent when master failover occurs during an active replication operation.

### Bug 20.2: Filer metadata cache staleness after network partition
- **Category:** Cache / Network partition
- **Description:** Filer metadata cache can serve stale data after network partition heals, as the cache invalidation mechanism doesn't properly handle partition recovery.

---

## Summary Statistics

| Project | Language | Bug Count | Categories |
|---------|----------|-----------|------------|
| etcd | Go | 12 | Race conditions, state inconsistency, deadlocks, data loss |
| TiKV | Rust | 7 | Memory leaks, data loss, deadlocks, raft state |
| CockroachDB | Go | 4 | Data loss, deadlocks, concurrent schema change |
| hashicorp/raft | Go | 5 | Memory leaks, deadlocks, snapshot issues |
| NATS Server | Go | 11 | Message loss, stream corruption, OOM, cluster recovery |
| Consul | Go | 3 | Certificate rotation, CA management |
| Nomad | Go | 5 | Scheduler panics, client disconnect, GC errors |
| Vitess | Go | 9 | Replication, failover, VDiff hang, vstream |
| Kubernetes | Go | 7 | Race conditions, scheduler, PV controller |
| TiDB | Go | 5 | Race conditions, DDL, query planning |
| CubeFS | Go | 5 | Decommission, readahead, distributed cache |
| Dragonboat | Go | 4 | Raft state, snapshot, node identity |
| Envoy | C++ | 4 | Segfaults, thread safety, config update |
| FoundationDB | C++ | 4 | DNS segfault, recovery, latency |
| containerd | Go | 4 | Blocking, resource calculation, lifecycle |
| Redis | C | 3 | Cluster failover, replication |
| gRPC | C++/Go | 3 | Concurrency, segfaults |
| Ceph | C++ | 4 | Data corruption, split-brain, deadlock |
| MinIO | Go | 3 | Erasure coding, distributed locks |
| SeaweedFS | Go | 2 | Replication, cache staleness |
| **Total** | | **105** | |

## Notes for Evaluation

### Bugs with Verified Fix Commits (Best for Evaluation)
The following bugs have verified fix commits, making them ideal for evaluation since you can check out the commit before the fix to reproduce:

1. etcd #20893 - Fix commit: `c58e6f1caf7dfe07da002230a2b61d664ab21a34`
2. etcd #20793 - Fix commit: `2e24a9845a3cd24fb52d676670e66c697f34336d`
3. etcd #14252 - Fix commit: `871d8fdaf1f817be10198828ed92910daeb2ec23`
4. TiKV #19393 - Fix commit: `055c58f6de7d05794169d049d9662c748aea48fb`
5. TiKV #19285 - Fix commit: `2d4737da47e4116fdd5c57276da9fdd844a5596d`
6. TiKV #19269 - Fix commit: `28ad2695b30b885ee59324fef49578386794f2d1`
7. TiKV #19238 - Fix commit: `42f84db052648dc140ce1eb1c7e272598c2ea235`
8. TiKV #19203 - Fix commit: `f9dbbeb454c93cc907ad7052dda307585769f213`
9. TiKV #19201 - Fix commit: `061b43a8f54ffef05da0d3bc48bddffee1096fc7`
10. CockroachDB #166122 - Fix commit: `8c90d1ad0b59f18926d3b77f9f653d942f755e36`
11. CockroachDB #159402 - Fix commit: `6a25c602c9745c480c5fb047da43b22cd11477d4`
12. CockroachDB #160337 - Fix commit: `e764212082e6e757030b527a14f5a5f7a396415d`
13. hashicorp/raft #362 - Fix commit: `7b09f38f739f486a692096c35236c7eef094e933`
14. hashicorp/raft #292 - Fix commit: `da92cfe76e0c1c9b94bbc9d884ec4b2b3b90b699`
15. hashicorp/raft #390 - Fix commit: `2e997410f28efe8106fc606d21cb655be1b05dee`
16. hashicorp/raft #213 - Fix commit: `37d2320db05ca622195063977ff5d4fbe0cd8ed8`
17. NATS #7720 - Fix commit: `b72becc443073300e5599d06fa0cde1cd5518589`
18. NATS #7725 - Fix commit: `6aded805ec9625b20ee50ded3b63135d5fe3d0a8`
19. Consul #16818 - Fix commit: `5560dcdbaecafc78a1475084af86a7b03db992e9`
20. Consul #16592 - Fix commit: `d5677e5680050a9b22403c160f5edde59613a4fc`
21. Nomad #27571 - Fix commit: `f95371693165852d0d58dca5b178a23c34d93819`
22. Vitess #19672 - Fix commit: `0da032e6382cf18231a3a251215b98f58234b88f`
23. Vitess #19666 - Fix commit: `b0279723f840b75299ca585e5f7c5be0a1853882`
24. Vitess #19515 - Fix commit: `db9c49fc8f6682c582e89ab4952c2b70488cba24`
25. Vitess #19432 - Fix commit: `42742eb78643366f65ec3acad6305ccc51922844`
26. Vitess #19413 - Fix commit: `c4af32913d2ff525716ebdff02256f6f1de584e8`
27. Vitess #19204 - Fix commit: `aae08bece30193c9fedabc015b2879dc4e88508b`
28. K8s #137719 - Fix commit: `c2a7819806ba6078330d495ac4ef274b2e2b3559`
29. TiDB #62946 - Fix commit: `be37b5a24abc1409504d9a8b2349c3ad05db8f2d`
30. TiDB #60004 - Fix commit: `797674c89918c7350a06eb0d91fa5e54390767f8`
31. TiDB #66910 - Fix commit: `732eea56e30d605aa7a2c32c6dbfeff9ef366e64`
32. Envoy #43526 - Fix commit: `2d83b4f5a298f3b24be802c5e246e4d7cb329abd`

### How to Use for Evaluation
For each bug with a verified fix commit:
1. `git clone <repo>`
2. `git checkout <fix_commit>~1` (check out the parent of the fix commit to get the buggy version)
3. Follow the reproduction steps listed in the bug entry
4. Use your distributed debugger to locate the bug
5. Compare your findings with the known root cause and fix
