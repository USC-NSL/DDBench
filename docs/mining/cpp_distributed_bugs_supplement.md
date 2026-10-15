> **Historical:** candidate-mining notes from the benchmark's construction. They include candidates that are not in the final 60-case benchmark (see [`index.md`](../../index.md)), and their commands and paths predate the current Docker workflow.

# C++ Distributed System Bugs - Supplement Report
## For Distributed Interactive Debugger Evaluation

**Generated: 2026-03-21**
**Total Additional C++ Bug Cases: 35**
**New C++ Projects: 5 (ScyllaDB, ClickHouse, YugabyteDB, Dragonfly, Seastar)**

---

## Table of Contents
1. [ScyllaDB (C++) - 10 bugs](#1-scylladb)
2. [ClickHouse (C++) - 7 bugs](#2-clickhouse)
3. [YugabyteDB (C++) - 6 bugs](#3-yugabytedb)
4. [Dragonfly (C++) - 7 bugs](#4-dragonfly)
5. [Seastar (C++) - 5 bugs](#5-seastar)

---

## 1. ScyllaDB

**Repository:** https://github.com/scylladb/scylladb
**Language:** C++ (built on Seastar framework)
**Description:** High-performance NoSQL database compatible with Apache Cassandra, using per-core sharding and Raft-based topology management

### Bug 1.1: Use-after-free in streaming_task_impl::run
- **Issue:** [#28200](https://github.com/scylladb/scylladb/issues/28200)
- **Category:** Use-after-free / Coroutine lifetime
- **Description:** In `storage_service::raft_topology_cmd_handler`, a lambda coroutine wrapped in `coroutine::lambda` is passed to `streaming_task_impl`. Since `coroutine::lambda` keeps a pointer to the lambda, when the task starts running the lambda may already be destroyed.
- **Root Cause:** `coroutine::lambda` stores a pointer to the lambda object, but the lambda's lifetime ends before the streaming task runs it asynchronously.
- **Reproduction Steps:**
  1. Run a ScyllaDB cluster
  2. Trigger a topology change that involves streaming (e.g., node join/decommission)
  3. Under certain timing, the streaming task runs after the lambda is destroyed
  4. Observe crash/corruption from use-after-free

### Bug 1.2: Raft topology IP->ID mapping lost on restart during replace
- **Issue:** [#28057](https://github.com/scylladb/scylladb/issues/28057)
- **Category:** Raft topology / Node replacement
- **Fix PR:** [#27435](https://github.com/scylladb/scylladb/pull/27435)
- **Fix Commit:** `af6cb0d0a431170d32ad7816c050f875298aa840`
- **Buggy Commit:** `af6cb0d0a431170d32ad7816c050f875298aa840~1`
- **Description:** The IP-to-ID mapping for a replacing node is only preserved for bootstrapping nodes, not for replacing nodes. If replace fails during streaming and all live nodes are restarted before rollback completes, all subsequent operations requiring the replacing node's IP will hit internal errors.
- **Reproduction Steps:**
  1. Start a multi-node ScyllaDB cluster
  2. Initiate a node replace operation
  3. Cause the replace to fail during streaming
  4. Shut down all live nodes before rollback completes
  5. Restart all nodes
  6. Run `nodetool status` - operations requiring the replacing node's IP fail with internal error

### Bug 1.3: Left node with stale leave request causes chain-crash
- **Issue:** [#27990](https://github.com/scylladb/scylladb/issues/27990)
- **Category:** Raft topology state machine / Chain crash
- **Description:** A `left` node can still have a `leave` (decommission) request in the topology state machine. This causes consecutive group0 leaders to crash at `topology_coordinator.cc:2271`, cascading until there's no majority.
- **Root Cause:** Bug in topology state machine cleanup - the leave request for a node that has already left is not properly cleaned up.
- **Buggy Version:** 2025.1.10
- **Reproduction Steps:**
  1. Run a ScyllaDB cluster (version 2025.1.10)
  2. Decommission a node
  3. Under certain conditions, the leave request persists for the already-left node
  4. Observe chain crash of group0 leaders
  5. Manual fix: delete the request on all nodes

### Bug 1.4: Missed notification in topology coordinator
- **Issue:** [#27958](https://github.com/scylladb/scylladb/issues/27958)
- **Category:** Race condition / Event notification
- **Description:** The topology coordinator loop has many deferred steps where the group0 guard is taken and released. If an event is signaled between guard release and the `await_event()` subscription, the notification is missed, delaying reaction by up to 60 seconds.
- **Root Cause:** Window between group0 guard release and event subscription where notifications can be lost. Tablet load stats refresh signals can arrive during processing steps.
- **Reproduction Steps:**
  1. Run ScyllaDB cluster with tablet-based workload
  2. Monitor topology coordinator reaction times
  3. Observe up to 60s delays in processing topology events

### Bug 1.5: Staging SSTables not discovered on restart causing view inconsistency
- **Issue:** [#27956](https://github.com/scylladb/scylladb/issues/27956)
- **Category:** Data inconsistency / Materialized views
- **Description:** Regression from `5d1f74b86ac6ef151871ee300f8728` that moved view update generator initialization before SSTable loading. Staging SSTables are left unprocessed indefinitely, causing base-view inconsistency and broken SSTable cleanup.
- **Root Cause:** View update generator initialization order changed - generator now initializes before SSTables are loaded, so it never discovers staging SSTables.
- **Buggy Commit:** `5d1f74b86ac6ef151871ee300f8728` (regression point)
- **Reproduction Steps:**
  1. Force a view update failure while writing data
  2. Restart the node
  3. Observe that staging SSTables are never processed
  4. Base table and materialized view become permanently inconsistent

### Bug 1.6: Memory corruption in repair with different shard counts
- **Issue:** [#27666](https://github.com/scylladb/scylladb/issues/27666)
- **Category:** Memory corruption / Repair
- **Severity:** P1
- **Fix PR:** [#26254](https://github.com/scylladb/scylladb/pull/26254)
- **Fix Commit:** `bbf9ce18efcabf2875298728dc3321a2b3c570b8`
- **Buggy Commit:** `bbf9ce18efcabf2875298728dc3321a2b3c570b8~1`
- **Description:** Memory corruption (segfault) when running repair between nodes with different shard counts. The multi-shard writer in the repair path corrupts memory.
- **Reproduction Steps:**
  1. Run a cluster where nodes have different `--smp` counts
  2. Trigger repair between nodes with different shard counts (`test_repair_disjoint_row_2nodes_diff_shard_count`)
  3. Observe segfault in `seastar::memory::small_pool::pop_free`

### Bug 1.7: Failed streaming leaves sealed SSTables on disk causing data resurrection
- **Issue:** [#27414](https://github.com/scylladb/scylladb/issues/27414)
- **Category:** Data resurrection / Streaming
- **Fix PR:** [#26528](https://github.com/scylladb/scylladb/pull/26528)
- **Fix Commit:** `bfdd4f77763651f5fc586feabe0fc5847fadd749`
- **Buggy Commit:** `bfdd4f77763651f5fc586feabe0fc5847fadd749~1`
- **Description:** If `add_sstable_and_update_cache()` fails after an SSTable is sealed during streaming, the SSTable remains on disk but invisible until restart. This can cause: (1) data resurrection after tombstone GC, (2) failure to restart after tablet split, (3) disk space accumulation.
- **Reproduction Steps:**
  1. Run a ScyllaDB cluster with tablet-based tables
  2. Trigger streaming (e.g., load balancing)
  3. Cause `add_sstable_and_update_cache()` to fail (e.g., topology guard violation)
  4. Observe sealed SSTables left on disk
  5. After restart, observe data resurrection if tombstones were GC'd

### Bug 1.8: Segfault when calling raft_topology/reload during startup
- **Issue:** [#27130](https://github.com/scylladb/scylladb/issues/27130)
- **Category:** Segfault / Race condition / Startup
- **Fix PR:** [#27410](https://github.com/scylladb/scylladb/pull/27410)
- **Fix Commit:** `e54abde3e851bbba8aca0a06085f234ea1f4b74a`
- **Buggy Commit:** `e54abde3e851bbba8aca0a06085f234ea1f4b74a~1`
- **Description:** Calling the `storage_service/raft_topology/reload` REST API endpoint during node startup causes a segfault because the REST API is set up before the storage service is fully initialized.
- **Reproduction Steps:**
  1. Start a ScyllaDB server
  2. In parallel, repeatedly call the REST endpoint:
     ```bash
     for i in $(seq 1 10); do sleep 1 && curl -X POST 'http://localhost:10000/storage_service/raft_topology/reload'; done
     ```
  3. Server crashes with segfault

### Bug 1.9: Topology barrier doesn't wait for closed sessions after drain failure
- **Issue:** [#26375](https://github.com/scylladb/scylladb/issues/26375)
- **Category:** Correctness / Tablet operations
- **Fix PR:** [#27492](https://github.com/scylladb/scylladb/pull/27492)
- **Fix Commit:** `af0b5d0894fd5f869c2e364f7e32bacc04c40d65`
- **Buggy Commit:** `af0b5d0894fd5f869c2e364f7e32bacc04c40d65~1`
- **Description:** In the `drain_failed = true` path of `global_token_metadata_barrier()`, the barrier may succeed even though closed sessions are still in use. This can leave aborted repair/streaming tasks running concurrently after tablet transition abort.
- **Root Cause:** When drain fails, the code skips waiting for closed sessions to become unused, goes straight to fence+barrier.

### Bug 1.10: Truncate check causes raft applier fiber to exit permanently
- **Issue:** [#25173](https://github.com/scylladb/scylladb/issues/25173)
- **Category:** Raft / Fatal error handling
- **Severity:** P1
- **Fix PR:** [#25174](https://github.com/scylladb/scylladb/pull/25174)
- **Fix Commit:** `bb922b2aa9dd58de902848d99fde06b9b1c5828a`
- **Buggy Commit:** `bb922b2aa9dd58de902848d99fde06b9b1c5828a~1`
- **Description:** TRUNCATE TABLE checks for concurrent writes and throws an exception via `on_internal_error()`. When truncate is called from DROP KEYSPACE/TABLE (raft operations), this exception is caught by the raft applier fiber's catch-all handler, which then exits, permanently disabling raft command execution on the node.
- **Reproduction Steps:**
  1. Start a ScyllaDB cluster
  2. Write data concurrently while dropping a keyspace or table
  3. The truncate check detects concurrent writes and throws
  4. Raft applier fiber exits, node can no longer execute raft commands

---

## 2. ClickHouse

**Repository:** https://github.com/ClickHouse/ClickHouse
**Language:** C++
**Description:** Column-oriented distributed OLAP database management system

### Bug 2.1: Background merges stuck on replicas requiring restart
- **Issue:** [#44865](https://github.com/ClickHouse/ClickHouse/issues/44865)
- **Category:** Replication / Merge stall
- **Description:** Background merges on a single replica suddenly stop and do not recover. Insert latencies increase and inserts fail due to "too many parts." Only a restart resolves the issue. Observed after upgrading from 22.3 to 22.12.
- **Buggy Version:** 22.12.1.1752
- **Reproduction Steps:**
  1. Run a ClickHouse cluster with ReplicatedMergeTree tables
  2. Under sustained insert load, observe one replica's background merges stopping
  3. Verify via `system.merges` that merges are stuck
  4. Insert latency increases, eventually "too many parts" errors appear
  5. Only restart resolves the issue

### Bug 2.2: Deadlock in ReplicatedMergeTreeQueue/MergeTreeBackgroundExecutor
- **Issue:** [#43816](https://github.com/ClickHouse/ClickHouse/issues/43816)
- **Category:** Deadlock / Replication
- **Description:** ClickHouse starts a part merge but never finishes it. Merges show 0 progress and the merge threads are stuck in `pthread_cond_wait` inside `ReplicatedMergeTreeQueue::CurrentlyExecuting::setActualPartName`.
- **Root Cause:** Deadlock between `ReplicatedMergeTreeQueue` lock and `MergeTreeBackgroundExecutor` when waiting for a concurrently executing entry.
- **Reproduction Steps:**
  1. Run a replicated ClickHouse cluster under write load
  2. Observe merges starting but never completing (progress stays at 0)
  3. Check `system.stack_trace` - merge threads are stuck in `setActualPartName`

### Bug 2.3: Logical error in JOIN with Merge table over Distributed
- **Issue:** [#75699](https://github.com/ClickHouse/ClickHouse/issues/75699)
- **Category:** Query execution / Distributed JOIN
- **Fix PR:** [#75454](https://github.com/ClickHouse/ClickHouse/pull/75454)
- **Fix Commit:** `9334d08f0c942a7402e88f3929f3252eb032722d`
- **Buggy Commit:** `9334d08f0c942a7402e88f3929f3252eb032722d~1`
- **Description:** LOGICAL_ERROR when performing JOIN between a Merge table and a Distributed table: "Column ID UInt32 query tree node does not have valid source node."
- **Reproduction Steps:**
  ```sql
  CREATE TABLE a (key UInt32) ENGINE = MergeTree ORDER BY key;
  CREATE TABLE b (key UInt32, ID UInt32) ENGINE = MergeTree ORDER BY key;
  CREATE TABLE aa (key UInt32) ENGINE = Distributed(test_cluster_two_shards, currentDatabase(), a, key);
  CREATE TABLE m (key UInt32) ENGINE = Merge(currentDatabase(), 'a');
  INSERT INTO a VALUES (0);
  INSERT INTO b VALUES (0, 1), (42, 1);
  SELECT * FROM m INNER JOIN b USING(key) WHERE ID = 1;  -- LOGICAL_ERROR
  ```

### Bug 2.4: Invalid number of rows in Chunk with Distributed table
- **Issue:** [#78074](https://github.com/ClickHouse/ClickHouse/issues/78074)
- **Category:** Query execution / Distributed JOIN
- **Fix PR:** [#98545](https://github.com/ClickHouse/ClickHouse/pull/98545)
- **Fix Commit:** `1b768fe2b4695dbb5d6b7534fe881e812852cb45`
- **Buggy Commit:** `1b768fe2b4695dbb5d6b7534fe881e812852cb45~1`
- **Description:** LOGICAL_ERROR "Invalid number of rows in Chunk" when performing queries on Distributed tables with specific JOIN settings.
- **Reproduction Steps:**
  1. Create a MergeTree table and a Distributed table wrapping it
  2. Insert data and run a JOIN query with `join_to_sort_minimum_perkey_rows = 0`
  3. Observe LOGICAL_ERROR

### Bug 2.5: Incorrect DISTINCT results over Distributed with optimize_skip_unused_shards
- **Issue:** [#92375](https://github.com/ClickHouse/ClickHouse/issues/92375)
- **Category:** Incorrect results / Distributed query
- **Fix PR:** [#92634](https://github.com/ClickHouse/ClickHouse/pull/92634)
- **Description:** `SELECT count() FROM (SELECT DISTINCT ... FROM distributed_table)` returns different results with `optimize_skip_unused_shards=0` vs `optimize_skip_unused_shards=1`. DISTINCT deduplication is not properly applied across shards.
- **Reproduction Steps:**
  ```sql
  CREATE TABLE data_local ENGINE=Memory() AS SELECT * FROM numbers(2);
  CREATE TABLE data_distributed AS data_local ENGINE=Distributed(test_cluster_two_shards, currentDatabase(), data_local, number);
  SELECT count() FROM (SELECT DISTINCT number FROM data_distributed) SETTINGS optimize_skip_unused_shards=0; -- returns 2
  SELECT count() FROM (SELECT DISTINCT number FROM data_distributed) SETTINGS optimize_skip_unused_shards=1; -- returns 4 (WRONG)
  ```

### Bug 2.6: Predicate pushdown produces wrong queries with distributed subqueries
- **Issue:** [#29332](https://github.com/ClickHouse/ClickHouse/issues/29332)
- **Category:** Query optimization / Distributed
- **Description:** Predicate pushdown with `enable_optimize_predicate_expression = 1` incorrectly rewrites queries containing IN subqueries on distributed tables, causing `DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED` errors or wrong results.
- **Reproduction Steps:**
  ```sql
  CREATE TABLE t_local(id UInt32, s String) ENGINE = MergeTree ORDER BY id;
  CREATE TABLE t_dist (id UInt32, s String) ENGINE = Distributed(test_cluster_two_shards, currentDatabase(), t_local);
  -- This fails with enable_optimize_predicate_expression=1 but works with =0
  SELECT * FROM (SELECT id, count() FROM t_dist GROUP BY id)
  WHERE id IN (SELECT id FROM t_dist WHERE notEmpty(s))
  SETTINGS enable_optimize_predicate_expression = 1, distributed_product_mode = 'deny';
  ```

### Bug 2.7: sum(Float64) GROUP BY produces different results depending on max_threads
- **Issue:** [#99109](https://github.com/ClickHouse/ClickHouse/issues/99109)
- **Category:** Non-determinism / Parallel aggregation
- **Description:** `sum(Float64)` GROUP BY returns different numerical results for the same static data when `max_threads` is changed. 78% of distinct keys yield different sum values between `max_threads=1` and `max_threads=8`.
- **Root Cause:** Floating-point addition is not associative. Different thread counts produce different partitioning and thus different summation orders.
- **Reproduction Steps:**
  1. Create a MergeTree table with Float64 values
  2. Insert deterministic data (200k rows)
  3. Run `SELECT sum(value) FROM t WHERE user_id = X GROUP BY user_id SETTINGS max_threads = 1`
  4. Run same query with `max_threads = 8`
  5. Observe different results (delta ~1e-14)

---

## 3. YugabyteDB

**Repository:** https://github.com/yugabyte/yugabyte-db
**Language:** C++ (DocDB storage layer) / Go / Java
**Description:** Distributed SQL database built on a modified version of RocksDB and Raft consensus

### Bug 3.1: Deadlocked transactions not interpreted as aborted
- **Issue:** [#30641](https://github.com/yugabyte/yugabyte-db/issues/30641)
- **Category:** Transaction handling / Deadlock detection
- **Description:** The `IsTxnAborted` function returns `false` for transactions aborted due to deadlock, incorrectly treating them as still active.
- **Root Cause:** The deadlock detection code paths set a different abort reason that `IsTxnAborted` doesn't recognize.
- **Buggy Version:** 2.29.0.0-b592

### Bug 3.2: DDL operations permanently blocked by orphaned object locks after PITR restore
- **Issue:** [#30639](https://github.com/yugabyte/yugabyte-db/issues/30639)
- **Category:** PITR / Object locks / Permanent block
- **Description:** After PITR (Point-In-Time Recovery) restore, DDL operations are permanently blocked with "Timed out waiting kResponseSent" errors. Orphaned object locks from pre-restore state block all subsequent DDL queries, even after 30+ minutes.
- **Root Cause:** Lock release RPCs are in-flight when PITR restore occurs. After restore, a tserver loses its lease and gets a new one, but stale locks from the old lease are not cleaned up. Master rejects cleanup because "TServer no longer has a live lease."
- **Reproduction Steps:**
  1. Start a 3-node RF=3 universe on 2.29.0.0-b592
  2. Create 400+ tables and run DDL workload (ADD_COLUMN, DROP_COLUMN, CHANGE_TYPE)
  3. Run nemesis (VM restart) on one tserver during DDL workload
  4. Perform PITR restore while object lock release RPCs are in-flight
  5. Attempt DROP on any table - all DDL queries fail permanently

### Bug 3.3: Core dumps from deadlock-aborted transactions in Raft apply
- **Issue:** [#30635](https://github.com/yugabyte/yugabyte-db/issues/30635)
- **Category:** FATAL / Raft apply / Deadlock
- **Severity:** High
- **Description:** Multiple tests fail with FATAL errors when applying write operations that were aborted due to deadlock detection. The FATAL occurs in `write_operation.cc:118` during `Replicated()`.
- **Buggy Version:** 2.29.0.0-b592
- **Reproduction Steps:**
  1. Run a YugabyteDB cluster with concurrent transactional workload
  2. Trigger deadlock conditions (conflicting transactions)
  3. Observe FATAL: "Apply operation failed: Transaction aborted due to a deadlock"

### Bug 3.4: Raft follower catch-up batch limit bug
- **Issue:** [#30437](https://github.com/yugabyte/yugabyte-db/issues/30437)
- **Category:** Raft / Follower catch-up
- **Description:** Bug in the batch size limiting logic when a Raft leader sends batches to catch up a follower. The limit check in `log_reader.h` doesn't work correctly, potentially sending oversized batches that exceed `rpc_max_message_size` and get rejected by the RPC layer.
- **Root Cause:** The `consensus_max_batch_size_bytes` limit is not properly enforced in the log reader's batch reading routine.

### Bug 3.5: Operations missing for vector index added during bootstrap
- **Issue:** [#30684](https://github.com/yugabyte/yugabyte-db/issues/30684)
- **Category:** Bootstrap / Index consistency
- **Description:** Vector indexes added during tablet bootstrap may miss operations. If multiple vector indexes exist and one is removed during bootstrap, it can lead to incorrect operation replay for remaining indexes.
- **Root Cause:** Flushed OpIds for vector indexes are determined at bootstrap start, but vector indexes can be added/removed during the bootstrap process.

### Bug 3.6: XCluster DDL replication context not cleared across schemas
- **Issue:** [#30529](https://github.com/yugabyte/yugabyte-db/issues/30529)
- **Category:** Cross-cluster replication / DDL
- **Severity:** Blocker (2025.2.2)
- **Description:** XCluster DDL replication fails when DDLs are run in different schemas. The xcluster context mapping uses incorrect schema name for cleanup, leaving stale entries that cause `Illegal state` errors on subsequent operations.
- **Root Cause:** Table creation uses `rel.relation_pgschema_name` for the mapping key but cleanup uses `query_info.schema`. When these don't match, stale entries accumulate.
- **Reproduction Steps:**
  ```sql
  CREATE SCHEMA test;
  CREATE TABLE test.foo(i int primary key);
  TRUNCATE test.foo;  -- Fails on target with "Illegal state ... already has entry in mapping"
  ```
  Workaround: `SET search_path TO <schema_name>` before running DDLs.

---

## 4. Dragonfly

**Repository:** https://github.com/dragonflydb/dragonfly
**Language:** C++
**Description:** Modern in-memory datastore compatible with Redis/Memcached APIs, with multi-threaded architecture

### Bug 4.1: Cluster mode crash - FLUSHSLOTS out-of-bounds
- **Issue:** [#6856](https://github.com/dragonflydb/dragonfly/issues/6856)
- **Category:** Crash / Cluster mode / Input validation
- **Fix PR:** [#6861](https://github.com/dragonflydb/dragonfly/pull/6861)
- **Fix Commit:** `c79bbe0c646c1bce47f76168dbe813951aecd8ce`
- **Buggy Commit:** `c79bbe0c646c1bce47f76168dbe813951aecd8ce~1`
- **Description:** DFLYCLUSTER FLUSHSLOTS with slot ID >= 16384 causes out-of-bounds crash: `bitset::set: __position (which is 16384) >= _Nb (which is 16384)`.
- **Root Cause:** Missing validation of slot IDs in DFLYCLUSTER FLUSHSLOTS command.
- **Reproduction Steps:**
  1. Start two Dragonfly instances in cluster mode
  2. Send DFLYCLUSTER FLUSHSLOTS with an invalid slot ID >= 16384
  3. Observe crash with SIGABRT

### Bug 4.2: Cluster mode crash - number overflow in config parsing
- **Issue:** [#6825](https://github.com/dragonflydb/dragonfly/issues/6825)
- **Category:** Crash / Cluster mode / Integer overflow
- **Fix PR:** [#6853](https://github.com/dragonflydb/dragonfly/pull/6853)
- **Fix Commit:** `4b16da4d2e80eafc57ecb5fef511a9d49afe5c54`
- **Buggy Commit:** `4b16da4d2e80eafc57ecb5fef511a9d49afe5c54~1`
- **Description:** Number overflow in DFLYCLUSTER CONFIG parsing causes assertion failure and crash.
- **Reproduction Steps:**
  1. Start two Dragonfly instances in cluster mode
  2. Send DFLYCLUSTER CONFIG with values causing integer overflow
  3. Observe crash: `Check failed: rb->RepliesRecorded() > replies_recorded_`

### Bug 4.3: Unresponsive during periodic expiration - 100% CPU
- **Issue:** [#6822](https://github.com/dragonflydb/dragonfly/issues/6822)
- **Category:** Livelock / CPU exhaustion
- **Fix PR:** [#6846](https://github.com/dragonflydb/dragonfly/pull/6846)
- **Fix Commit:** `4df1a91450cd504c37bff5730944a3569996abff`
- **Buggy Commit:** `4df1a91450cd504c37bff5730944a3569996abff~1`
- **Description:** Dragonfly becomes completely unresponsive consuming 100% CPU during periodic key expiration. The `DashTable::Traverse` in `DeleteExpiredStep` runs without yielding, blocking all other operations on the proactor thread.
- **Root Cause:** The expiration traversal doesn't yield back to the event loop, causing the proactor thread to be monopolized.
- **Reproduction Steps:**
  1. Run Dragonfly with many keys that have expiration times
  2. Wait for periodic expiration to trigger
  3. During unresponsive periods, observe 100% CPU on Proactor0
  4. Perf profile shows 91.92% time in `DeleteExpiredStep` -> `DashTable::Traverse`

### Bug 4.4: Blocking commands in pipeline don't flush replies
- **Issue:** [#6738](https://github.com/dragonflydb/dragonfly/issues/6738)
- **Category:** Pipeline / Blocking commands / Compatibility
- **Severity:** Urgent
- **Fix PR:** [#6743](https://github.com/dragonflydb/dragonfly/pull/6743)
- **Fix Commit:** `c4849b4d008d1dd6fd950f251cdb9a9a2e264e00`
- **Buggy Commit:** `c4849b4d008d1dd6fd950f251cdb9a9a2e264e00~1`
- **Description:** `BRPOPLPUSH` clients are not unblocked when `LPUSH`/`RPUSH` happens inside a Lua script (`EVALSHA`/`EVAL`). Workers wait for full timeout instead of waking immediately. Causes 15-50s webhook response times instead of ~1.5s in production with Bull/n8n.
- **Root Cause:** Replies are not flushed when encountering a blocking command in a pipeline. The dest shard is not woken when the source shard is awakened.
- **Reproduction Steps:**
  1. Deploy Dragonfly with `--default_lua_flags=allow-undeclared-keys`
  2. Run a Bull-based application (e.g., n8n in queue mode)
  3. Workers use `BRPOPLPUSH` with 5s timeout, jobs enqueued via `EVALSHA` containing `RPUSH`
  4. Observe workers only pick up jobs after timeout (5s) instead of immediately

### Bug 4.5: Crash in db_slice.cc during concurrent operations
- **Issue:** [#6862](https://github.com/dragonflydb/dragonfly/issues/6862)
- **Category:** Crash / Concurrent access
- **Description:** Crash at `db_slice.cc:550` during concurrent operations in cluster mode.

### Bug 4.6: Crash in doc_accessors.cc
- **Issue:** [#6907](https://github.com/dragonflydb/dragonfly/issues/6907)
- **Category:** Crash / JSON operations
- **Description:** Crash at `doc_accessors.cc:60` during JSON document access operations.

### Bug 4.7: Multiple crash modes in cluster
- **Issue:** [#6909](https://github.com/dragonflydb/dragonfly/issues/6909)
- **Category:** Crash / Cluster stability
- **Description:** Dragonfly crashes in multiple different ways under cluster mode operations, indicating systemic stability issues in the cluster implementation.

---

## 5. Seastar

**Repository:** https://github.com/scylladb/seastar
**Language:** C++
**Description:** High-performance server-side application framework with per-core sharding, used by ScyllaDB

### Bug 5.1: Cross-shard realloc shrink crashes
- **Issue:** [#2202](https://github.com/scylladb/seastar/issues/2202)
- **Category:** Memory management / Cross-shard
- **Description:** If a pointer is allocated on one shard and reallocated smaller on another shard, it crashes with an assertion failure: `object_cpu_id(ptr) == cpu_id`. This violates the general contract of `realloc()`.
- **Root Cause:** Cross-shard `realloc` to a smaller size is not handled like cross-core frees. The shrink path asserts that the object belongs to the current CPU.
- **Reproduction Steps:**
  ```cpp
  SEASTAR_TEST_CASE(test_cross_thread_realloc) {
      void *p = malloc(100);
      auto other_shard = (this_shard_id() + 1) % smp::count;
      return smp::submit_to(other_shard, [p]{
          BOOST_REQUIRE(realloc(p, 50));  // CRASHES
      });
  }
  ```

### Bug 5.2: coroutine::parallel_for_each use-after-free
- **Issue:** [#1902](https://github.com/scylladb/seastar/issues/1902)
- **Category:** Use-after-free / Coroutine
- **Fix PR:** [#1903](https://github.com/scylladb/seastar/pull/1903)
- **Fix Commit:** `830ce8673845a8394b2c0845ba396aff6a16ede0`
- **Buggy Commit:** `830ce8673845a8394b2c0845ba396aff6a16ede0~1`
- **Description:** `coroutine::parallel_for_each` breaks the rule that every task must stay alive from resume until control returns to the reactor. When it finishes, it resumes the parent coroutine and destroys itself. The reactor's `_current_task` pointer is left dangling. If `current_tasktrace()` is called, undefined behavior occurs.
- **Root Cause:** The parallel_for_each task object is destroyed after resuming the parent coroutine but before control returns to the reactor.

### Bug 5.3: Heap-use-after-free in RPC connection::stop_send_loop
- **Issue:** [#1137](https://github.com/scylladb/seastar/issues/1137)
- **Category:** Use-after-free / RPC
- **Description:** ASAN detects heap-use-after-free in RPC `connection::stop_send_loop` during bootstrap with parallel writes when a peer connection is reset. Found during ScyllaDB cluster bootstrap testing.
- **Reproduction Steps:**
  1. Run a ScyllaDB cluster bootstrap with debug/ASAN build
  2. Kill a node during streaming with parallel writes
  3. Observe ASAN heap-use-after-free in `rpc connection::stop_send_loop`

### Bug 5.4: No timer callback after periodic timer cancellation
- **Issue:** [#3013](https://github.com/scylladb/seastar/issues/3013)
- **Category:** Timer / Event loop
- **Description:** After cancelling a periodic timer, the timer callback is never invoked again, even if the timer is re-armed.

### Bug 5.5: Assertion failure when HTTP server listens on taken port with multiple cores
- **Issue:** [#2036](https://github.com/scylladb/seastar/issues/2036)
- **Category:** Assertion failure / Multi-core
- **Description:** When an HTTP server attempts to listen on a port that is already taken, the error handling path triggers an assertion failure specifically on multi-core configurations.

---

## Summary

| Project | Language | Bug Count | Key Bug Types |
|---------|----------|-----------|--------------|
| ScyllaDB | C++ | 10 | Raft topology, use-after-free, memory corruption, data resurrection, chain crashes |
| ClickHouse | C++ | 7 | Distributed JOIN errors, merge deadlocks, incorrect results, replication stalls |
| YugabyteDB | C++ | 6 | Deadlock detection, PITR restore, Raft follower catch-up, XCluster replication |
| Dragonfly | C++ | 7 | Cluster mode crashes, CPU exhaustion, pipeline blocking, integer overflow |
| Seastar | C++ | 5 | Cross-shard memory, use-after-free, RPC, coroutine lifetime |
| **Total** | | **35** | |

## Bugs with Verified Fix Commits (Best for Evaluation)

| # | Project | Issue | Fix Commit | Description |
|---|---------|-------|------------|-------------|
| 1 | ScyllaDB | #28057 | `af6cb0d0a431170d32ad7816c050f875298aa840` | Raft topology IP->ID mapping lost on restart |
| 2 | ScyllaDB | #27666 | `bbf9ce18efcabf2875298728dc3321a2b3c570b8` | Memory corruption in repair with different shard counts |
| 3 | ScyllaDB | #27414 | `bfdd4f77763651f5fc586feabe0fc5847fadd749` | Failed streaming leaves sealed SSTables |
| 4 | ScyllaDB | #27130 | `e54abde3e851bbba8aca0a06085f234ea1f4b74a` | Segfault on raft_topology/reload during startup |
| 5 | ScyllaDB | #26375 | `af0b5d0894fd5f869c2e364f7e32bacc04c40d65` | Topology barrier skips session drain check |
| 6 | ScyllaDB | #25173 | `bb922b2aa9dd58de902848d99fde06b9b1c5828a` | Truncate check exits raft applier fiber |
| 7 | ClickHouse | #75699 | `9334d08f0c942a7402e88f3929f3252eb032722d` | Logical error in JOIN Merge over Distributed |
| 8 | ClickHouse | #78074 | `1b768fe2b4695dbb5d6b7534fe881e812852cb45` | Invalid rows in Chunk with distributed table |
| 9 | Dragonfly | #6856 | `c79bbe0c646c1bce47f76168dbe813951aecd8ce` | Cluster FLUSHSLOTS out-of-bounds crash |
| 10 | Dragonfly | #6825 | `4b16da4d2e80eafc57ecb5fef511a9d49afe5c54` | Cluster CONFIG number overflow crash |
| 11 | Dragonfly | #6822 | `4df1a91450cd504c37bff5730944a3569996abff` | 100% CPU during periodic expiration |
| 12 | Dragonfly | #6738 | `c4849b4d008d1dd6fd950f251cdb9a9a2e264e00` | Blocking commands in pipeline not flushed |
| 13 | Seastar | #1902 | `830ce8673845a8394b2c0845ba396aff6a16ede0` | parallel_for_each use-after-free |

### How to Use for Evaluation
For each bug with a verified fix commit:
1. `git clone <repo>`
2. `git checkout <fix_commit>~1` (parent of fix commit = buggy version)
3. Build the project (follow project's build instructions)
4. Follow the reproduction steps listed in the bug entry
5. Use your distributed debugger to locate the bug
6. Compare your findings with the known root cause and fix
