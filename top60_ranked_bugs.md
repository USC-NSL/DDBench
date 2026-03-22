# Top 60 Easiest-to-Deploy & Easiest-to-Reproduce Distributed System Bugs
## For Distributed Interactive Debugger Evaluation

**Generated: 2026-03-21**
**Total Ranked Bugs: 60**

---

## Scoring Methodology

Each bug is scored on two axes (1 = easiest, 10 = hardest):

### Deploy Score (how hard is it to build from source + set up a debuggable cluster)
| Score | Meaning | Examples |
|-------|---------|---------|
| 1-2 | Single `go build` / `make`, single binary, trivial multi-node via CLI flags | etcd, NATS, Consul |
| 3 | Single binary but needs cmake/cargo, or minor external deps | CockroachDB, Dragonfly, hashicorp/raft, Nomad, Kvrocks, RocksDB |
| 4-5 | Moderate C++ build (CMake), or multiple components | ClickHouse, Seastar, FoundationDB, Redpanda |
| 6-7 | Heavy build chain, multiple required services (PD, MySQL, etc.) | TiKV, ScyllaDB, Vitess, YugabyteDB |
| 8-10 | Very complex multi-component system | Kubernetes, Ceph |

### Reproduce Score (how hard is it to trigger the bug once deployed)
| Score | Meaning |
|-------|---------|
| 1 | Deterministic, has a script/test/SQL that triggers it every time |
| 2 | Clear step-by-step instructions, triggers reliably |
| 3 | Reliable with specific config, may need a short workload |
| 4 | Needs moderate setup (cluster operations, specific workload) |
| 5 | Requires failure injection or specific timing, but documented |
| 6-7 | Race condition or timing dependent, may need multiple attempts |
| 8-10 | Sporadic, needs long runtime, special hardware, or extreme scale |

### Combined Score = Deploy + Reproduce (lower is better)

---

## Full Rankings (#1–#60, sorted by combined score)

| Rank | Combined | Deploy | Repro | Lang | Project | Issue | Bug Summary |
|------|----------|--------|-------|------|---------|-------|-------------|
| 1 | 4 | 3 | 1 | C++ | Dragonfly | #6856 | Cluster FLUSHSLOTS out-of-bounds crash |
| 2 | 4 | 3 | 1 | C++ | Dragonfly | #6825 | Cluster CONFIG number overflow crash |
| 3 | 4 | 3 | 1 | C++ | Dragonfly | #6753 | SIGFPE crash in DEBUG POPULATE with val_size=0 |
| 4 | 4 | 3 | 1 | C++ | Dragonfly | #6619 | Crash on EVALSHA with empty SHA |
| 5 | 4 | 3 | 1 | C++ | Dragonfly | #6761 | Crash on memcache STATS/VERSION in pipeline |
| 6 | 4 | 3 | 1 | C++ | Dragonfly | #6614 | Crash from double-add MONITOR in MULTI/EXEC |
| 7 | 4 | 3 | 1 | C++ | Dragonfly | #6907 | Crash on wrong-sized vector/numeric in FT.SEARCH |
| 8 | 4 | 3 | 1 | C++ | Dragonfly | #6764 | Crash on HINCRBYFLOAT with NaN/Inf |
| 9 | 4 | 3 | 1 | C++ | Kvrocks | #3315 | Crash on `zdiff 0 a` |
| 10 | 4 | 2 | 2 | Go | NATS | #7760 | Consumer filter stops matching after leader step-down |
| 11 | 4 | 2 | 2 | Go | etcd | #20893 | --force-new-cluster can't remove learners |
| 12 | 4 | 2 | 2 | Go | etcd | #19172 | Data race when closing embedded etcd |
| 13 | 5 | 3 | 2 | C++ | Dragonfly | #6909 | Crash from non-finite NUMERIC + KeepTopKSorted OOB |
| 14 | 5 | 3 | 2 | C++ | Dragonfly | #6654 | Crash in memcache reply_builder for large values |
| 15 | 5 | 3 | 2 | C++ | Dragonfly | #6819 | Crash from stale expiry when overwriting key |
| 16 | 5 | 3 | 2 | C++ | Dragonfly | #6766 | Crash in json_family - memory tracking orphans |
| 17 | 5 | 3 | 2 | C++ | Dragonfly | #6912 | Crash in rdb_save - unknown encoding for type 17 |
| 18 | 5 | 3 | 2 | C++ | Kvrocks | #3148 | `namespace set` deletes another namespace |
| 19 | 5 | 2 | 3 | Go | NATS | #7817 | Messages lost with WorkQueue retention R3 |
| 20 | 5 | 2 | 3 | Go | NATS | #7726 | Mixed wildcard/literal filter fails delivery |
| 21 | 5 | 2 | 3 | Go | etcd | #20655 | Fast watch creation breaks reliable watch |
| 22 | 5 | 2 | 3 | Go | etcd | #20704 | Linearizability bugs in leasing cache |
| 23 | 5 | 3 | 2 | Go | hashicorp/raft | #358 | Snapshot deletes negative log range |
| 24 | 6 | 5 | 1 | C++ | ClickHouse | #92375 | Incorrect DISTINCT over distributed table |
| 25 | 6 | 5 | 1 | C++ | ClickHouse | #99109 | sum(Float64) non-deterministic with max_threads |
| 26 | 6 | 5 | 1 | C++ | ClickHouse | #43816 | Deadlock in ReplicatedMergeTreeQueue merge wait |
| 27 | 6 | 5 | 1 | C++ | Seastar | #2202 | Cross-shard realloc shrink crashes |
| 28 | 6 | 3 | 3 | C++ | Dragonfly | #6822 | 100% CPU during periodic key expiration |
| 29 | 6 | 3 | 3 | C++ | Dragonfly | #6738 | Blocking commands in pipeline not flushed |
| 30 | 6 | 3 | 3 | C++ | Dragonfly | #6687 | Replica sync retry loop - unknown RDB encoding 62 |
| 31 | 6 | 3 | 3 | C++ | Kvrocks | #3356 | Replication feed thread blocks, WAL exhaustion |
| 32 | 6 | 3 | 3 | C++ | Kvrocks | #3339 | XREADGROUP BLOCK sends double response |
| 33 | 6 | 3 | 3 | Go | hashicorp/raft | #212 | Out-of-date followers stuck in snapshot loop |
| 34 | 6 | 3 | 3 | Go | hashicorp/raft | #291 | Node failure triggers OOM via verifyLeader |
| 35 | 6 | 3 | 3 | Go | CockroachDB | #166122 | Partial index data loss during concurrent update |
| 36 | 6 | 2 | 4 | Go | NATS | #7718 | Subscription leak with OrderedConsumer churn |
| 37 | 6 | 2 | 4 | Go | NATS | #6888 | JetStream stream lost after kill -9 |
| 38 | 7 | 5 | 2 | C++ | ClickHouse | #75699 | Logical error in JOIN Merge over Distributed |
| 39 | 7 | 5 | 2 | C++ | ClickHouse | #78074 | Invalid rows in Chunk with distributed table |
| 40 | 7 | 5 | 2 | C++ | ClickHouse | #29332 | Predicate pushdown wrong with distributed IN |
| 41 | 7 | 5 | 2 | C++ | ClickHouse | #40571 | Keeper crashes on every startup with segfault |
| 42 | 7 | 5 | 2 | C++ | ClickHouse | #98079 | Keeper disconnects after addWatch() |
| 43 | 7 | 5 | 2 | C++ | ClickHouse | #44865 | Background merges stuck on replicas |
| 44 | 7 | 5 | 2 | C++ | Redpanda | #25769 | ListOffsets returns incorrect results |
| 45 | 7 | 7 | 1 | C++ | ScyllaDB | #27130 | Segfault on raft_topology/reload during startup |
| 46 | 7 | 3 | 4 | Go | Nomad | #27567 | Scheduler panic during eval processing |
| 47 | 7 | 3 | 4 | Go | hashicorp/raft | #268 | Shutdown() deadlock with takeSnapshot() |
| 48 | 7 | 3 | 4 | C++ | Dragonfly | #6862 | Crash in db_slice during concurrent ops |
| 49 | 7 | 2 | 5 | Go | etcd | #20657 | Race between snapshot cleanup and application |
| 50 | 7 | 2 | 5 | Go | etcd | #20269 | Panic on member rejoin after reset |
| 51 | 7 | 2 | 5 | Go | etcd | #20793 | Learner promotion not persisted across upgrades |
| 52 | 7 | 2 | 5 | Go | NATS | #7852 | Subject filtering perf degradation |
| 53 | 8 | 5 | 3 | C++ | Redpanda | #15118 | Future assert under load in kafka client |
| 54 | 8 | 5 | 3 | C++ | Redpanda | #16944 | Oversized allocation in raft::replicate_batcher |
| 55 | 8 | 7 | 1 | C++ | ScyllaDB | #28200 | Use-after-free in streaming_task_impl::run |
| 56 | 8 | 7 | 1 | C++ | ScyllaDB | #25173 | Truncate exits raft applier fiber permanently |
| 57 | 8 | 3 | 5 | C++ | RocksDB | #10751 | Stalled writes block forever during shutdown |
| 58 | 8 | 3 | 5 | C++ | RocksDB | #13652 | ExportColumnFamily misses committed data |
| 59 | 9 | 7 | 2 | C++ | ScyllaDB | #28057 | Raft topology IP->ID mapping lost on restart |
| 60 | 9 | 7 | 2 | C++ | ScyllaDB | #27956 | Staging SSTables not discovered causing view inconsistency |

---

## Detailed Bug Profiles

---

### #1. Dragonfly #6856 — Cluster FLUSHSLOTS out-of-bounds crash
**Deploy: 3 | Reproduce: 1 | Combined: 4**

- **Language:** C++
- **Repository:** https://github.com/dragonflydb/dragonfly
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6856
- **Category:** Crash / Input validation / Cluster mode
- **Fix Commit:** `c79bbe0c646c1bce47f76168dbe813951aecd8ce`
- **Buggy Commit:** `c79bbe0c646c1bce47f76168dbe813951aecd8ce~1`

**Why easy to deploy:** Single CMake build, single binary, cluster mode with just CLI flags.

**Why easy to reproduce:** Has a complete replay script that triggers the crash deterministically.

**Setup:**
```bash
git clone https://github.com/dragonflydb/dragonfly && cd dragonfly
git checkout c79bbe0c646c1bce47f76168dbe813951aecd8ce~1
./helio/blaze.sh  # or cmake
```

**Reproduce:**
```bash
# Terminal 0:
./build/dragonfly --port 6380 --logtostderr --proactor_threads 1 --dbfilename="" \
    --cluster_mode=yes --cluster_node_id=0000000000000000000000000000000000000000
# Terminal 1:
./build/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename="" \
    --cluster_mode=yes --cluster_node_id=1111111111111111111111111111111111111111 --hz=0
# Terminal 2: replay the crash script from the issue attachment
python3 replay_crash.py crashes 000000
```

**Root Cause:** Missing validation of slot IDs in DFLYCLUSTER FLUSHSLOTS — slot ID >= 16384 causes `bitset::set` out-of-bounds.

---

### #2. Dragonfly #6825 — Cluster CONFIG number overflow crash
**Deploy: 3 | Reproduce: 1 | Combined: 4**

- **Language:** C++
- **Repository:** https://github.com/dragonflydb/dragonfly
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6825
- **Category:** Crash / Integer overflow / Cluster mode
- **Fix Commit:** `4b16da4d2e80eafc57ecb5fef511a9d49afe5c54`
- **Buggy Commit:** `4b16da4d2e80eafc57ecb5fef511a9d49afe5c54~1`

**Why easy to reproduce:** Has a complete replay script. Deterministic.

**Setup:** Same as #1 (two Dragonfly instances in cluster mode).

**Reproduce:**
```bash
# Same two-node cluster setup as #1
# Terminal 2: replay the crash script from the issue attachment
python3 replay_crash.py crashes 000000
```

**Root Cause:** Number overflow in DFLYCLUSTER CONFIG parsing causes assertion failure.

---

### #3. Dragonfly #6753 — SIGFPE crash in DEBUG POPULATE with val_size=0
**Deploy: 3 | Reproduce: 1 | Combined: 4**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6753
- **Fix Commit:** `5e31c9f84acfcfc2a7fb421cde7845ffcdf5536e`
- **Buggy Commit:** `5e31c9f84acfcfc2a7fb421cde7845ffcdf5536e~1`
- **Category:** Crash / Division-by-zero

**Reproduce:**
```bash
./build/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
# In another terminal:
redis-cli -p 6379 DEBUG POPULATE 100 prefix 0
# SIGFPE (division by zero) in DoPopulateBatch()
```

**Root Cause:** Division by zero when `val_size` parameter is 0.

---

### #4. Dragonfly #6619 — Crash on EVALSHA with empty SHA
**Deploy: 3 | Reproduce: 1 | Combined: 4**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6619
- **Fix Commit:** `761387a51433a5becb06db2ac7bf7e9f18b832d2`
- **Buggy Commit:** `761387a51433a5becb06db2ac7bf7e9f18b832d2~1`
- **Category:** Crash / Input validation

**Reproduce:**
```bash
./dragonfly --logtostderr --proactor_threads=1 --dbfilename=""
# Replay from issue attachment, or:
redis-cli EVALSHA "" 0
# FATAL: Check failed: !eval_args.sha.empty()
```

**Root Cause:** No validation for empty SHA in EVALSHA command.

---

### #5. Dragonfly #6761 — Crash on memcache STATS/VERSION in pipeline
**Deploy: 3 | Reproduce: 1 | Combined: 4**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6761
- **Fix Commit:** `5a78b758ff21f179963de4da9e7ad301459e23bb`
- **Buggy Commit:** `5a78b758ff21f179963de4da9e7ad301459e23bb~1`
- **Category:** Crash / Memcache protocol

**Reproduce:**
```bash
./dragonfly --port 6379 --memcached_port=11211 --logtostderr --proactor_threads 1 --dbfilename=""
# Replay the crash archive from the issue attachment
python3 replay_crash.py crashes 000000 127.0.0.1 11211
```

**Root Cause:** STATS/VERSION commands return WOULD_BLOCK in memcache pipeline mode without proper handling.

---

### #6. Dragonfly #6614 — Crash from double-add MONITOR in MULTI/EXEC
**Deploy: 3 | Reproduce: 1 | Combined: 4**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6614
- **Fix Commit:** `84034d0903e8409dd48adcce974e5250d357a7ce`
- **Buggy Commit:** `84034d0903e8409dd48adcce974e5250d357a7ce~1`
- **Category:** Crash / MULTI/EXEC

**Reproduce:**
```bash
./dragonfly --logtostderr --proactor_threads=1 --dbfilename=""
redis-cli
> MULTI
> MONITOR
> MONITOR
> EXEC
# FATAL: Check failed: cc_
```

**Root Cause:** `ChangeMonitor` not idempotent — calling MONITOR twice in MULTI/EXEC adds it twice, causing assertion failure.

---

### #7. Dragonfly #6907 — Crash on wrong-sized vector/numeric in FT.SEARCH
**Deploy: 3 | Reproduce: 1 | Combined: 4**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6907
- **Fix Commit:** `c09a5a16bacc4b107435b0f144c1eb4a7553fd04`
- **Buggy Commit:** `c09a5a16bacc4b107435b0f144c1eb4a7553fd04~1`
- **Category:** Crash / Search / Input validation

**Reproduce:**
```bash
./dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
# Create a search index with VECTOR/NUMERIC fields
# Insert documents with wrong-sized values
# Run FT.SEARCH → crash at doc_accessors.cc:60
```

**Root Cause:** No validation for field value sizes in FT.SEARCH — wrong-sized vector or numeric fields cause out-of-bounds access.

---

### #8. Dragonfly #6764 — Crash on HINCRBYFLOAT with NaN/Inf
**Deploy: 3 | Reproduce: 1 | Combined: 4**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6764
- **Fix Commit:** `01ce1ca9ea6c429e531d6177f72963b1fd29c26d`
- **Buggy Commit:** `01ce1ca9ea6c429e531d6177f72963b1fd29c26d~1`
- **Category:** Crash / Floating-point

**Reproduce:**
```bash
redis-cli
> HSET myhash field 1.0
> HINCRBYFLOAT myhash field inf
# Crash at hset_family.cc:973 — empty hash left after NaN/Inf result
```

**Root Cause:** HINCRBYFLOAT doesn't prevent NaN/Inf values from being stored, which creates an invalid empty hash state.

---

### #9. Kvrocks #3315 — Crash on `zdiff 0 a`
**Deploy: 3 | Reproduce: 1 | Combined: 4**

- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/3315
- **Fix Commit:** `c2c5d094d4335c4951f88e7de319d78e1bf5b3b8`
- **Buggy Commit:** `c2c5d094d4335c4951f88e7de319d78e1bf5b3b8~1`
- **Category:** Crash / Input validation

**Why easy to deploy:** CMake build, single binary, Redis-compatible.

**Reproduce:**
```bash
git clone https://github.com/apache/kvrocks && cd kvrocks
git checkout c2c5d094d4335c4951f88e7de319d78e1bf5b3b8~1
mkdir build && cd build && cmake .. && make -j
./kvrocks -p 6666
# In another terminal:
redis-cli -p 6666 ZDIFF 0 a
# CRASH
```

**Root Cause:** `zdiff` with numkeys=0 isn't handled, causing out-of-bounds access.

---

### #10. NATS Server #7760 — Consumer filter subjects stop matching after leader step-down
**Deploy: 2 | Reproduce: 2 | Combined: 4**

- **Language:** Go
- **Repository:** https://github.com/nats-io/nats-server
- **Issue:** https://github.com/nats-io/nats-server/issues/7760
- **Category:** Consumer state loss / Leader election
- **Fix PR:** [#7773](https://github.com/nats-io/nats-server/pull/7773)
- **Buggy Version:** v2.12.3

**Reproduce:**
```bash
# 1. Create stream and consumer
nats stream add foo-stream --subjects "foo.>" --replicas 5 --storage file \
  --retention interest --ack --discard old --dupe-window 2m --no-allow-direct
nats consumer add foo-stream foo-consumer --pull --filter "foo.bar" --filter "foo.bar1" \
  --deliver all --ack explicit --replay instant --max-deliver 20 --max-pending 1000

# 2. Verify it works
nats pub "foo.bar" 'check {{ .Count }}' --sleep 1s --count 5
nats consumer next foo-stream foo-consumer --wait 2s --count 5  # Should get messages

# 3. Edit consumer filter subjects (add/change a filter)
# 4. Step down consumer leader
nats consumer cluster step-down foo-stream foo-consumer

# 5. Publish more messages
nats pub "foo.bar" 'after stepdown {{ .Count }}' --sleep 1s --count 5

# 6. Try to consume — FAILS (timeout, 0 unprocessed messages)
nats consumer next foo-stream foo-consumer --wait 2s --count 5
```

**Root Cause:** Interest stream desync after consumer filter update + leader step-down.

---

### #11. etcd #20893 — --force-new-cluster can't remove learners after snapshot
**Deploy: 2 | Reproduce: 2 | Combined: 4**

- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/20893
- **Category:** Cluster recovery / Learner cleanup
- **Fix Commit:** `c58e6f1caf7dfe07da002230a2b61d664ab21a34`
- **Buggy Commit:** `c58e6f1caf7dfe07da002230a2b61d664ab21a34~1`

**Reproduce:**
```bash
# 1. Create a 3-member cluster with --snapshot-count=2
# 2. Add a new learner
# 3. Write >2 keys to trigger snapshot
for i in $(seq 1 5); do etcdctl put key$i val$i; done
# 4. Stop all etcd members
# 5. Start one member with --force-new-cluster
# 6. Verify: learner is still present (BUG)
etcdctl member list
```

**Root Cause:** `server/storage/util.go:121-123` only considers voting members when forcing single-member cluster, ignoring learners in the snapshot.

---

### #12. etcd #19172 — Data race when closing embedded etcd
**Deploy: 2 | Reproduce: 2 | Combined: 4**

- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/19172
- **Category:** Data race

**Reproduce:**
```bash
cd server
go test -race -run TestEmbedEtcd ./embed/
# Observe: WARNING: DATA RACE between Etcd.Close() and Etcd.errHandler()
```

**Root Cause:** Unsynchronized write in `Close()` and read in `errHandler()` to the same field in the `Etcd` struct.

---

### #13. Dragonfly #6909 — Crash from non-finite NUMERIC + KeepTopKSorted OOB
**Deploy: 3 | Reproduce: 2 | Combined: 5**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6909
- **Fix Commit:** `1c38bb63d2824080430d6d25e5a6fe6d714a2882`
- **Buggy Commit:** `1c38bb63d2824080430d6d25e5a6fe6d714a2882~1`

**Reproduce:** Create search index, insert documents with non-finite numeric values or trigger KeepTopKSorted with boundary conditions. Replay crash archive from issue.

---

### #14. Dragonfly #6654 — Crash in memcache reply_builder for large values
**Deploy: 3 | Reproduce: 2 | Combined: 5**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6654
- **Fix Commit:** `ff4ef508985cb91a7fdf418682af1534c24acf83`
- **Buggy Commit:** `ff4ef508985cb91a7fdf418682af1534c24acf83~1`

**Reproduce:**
```bash
./dragonfly --port 6379 --memcached_port=11211 --proactor_threads 1 --dbfilename="" --max_bulk_len=1048576
python3 replay_crash.py crashes 000002 127.0.0.1 11211
# FATAL: Check failed: expected_buffer_cap <= kMaxBufferSize (8242 vs. 8192)
```

**Root Cause:** Meta get response for large values exceeds `kMaxBufferSize`.

---

### #15. Dragonfly #6819 — Crash from stale expiry when overwriting key
**Deploy: 3 | Reproduce: 2 | Combined: 5**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6819
- **Fix Commit:** `fa4d116313779182571f70a537ab31f09ec043a5`
- **Buggy Commit:** `fa4d116313779182571f70a537ab31f09ec043a5~1`

**Reproduce:**
```bash
redis-cli
> SET mykey myval EX 60       # Set key with expiry
> SET mykey newval             # Overwrite WITHOUT expiry
# Under certain timing, crash at db_slice.cc:1163
```

**Root Cause:** Stale expiry entry not cleared when key is overwritten with no expiration.

---

### #16. Dragonfly #6766 — Crash in json_family - memory tracking orphans
**Deploy: 3 | Reproduce: 2 | Combined: 5**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6766
- **Fix Commit:** `f3ee1ad3ef1bd6c5bbdb2e26b1c380e324602fed`
- **Buggy Commit:** `f3ee1ad3ef1bd6c5bbdb2e26b1c380e324602fed~1`

**Reproduce:** Perform JSON operations that create orphaned objects (rapid JSON.SET + DEL cycles on nested structures). Crash at `json_family.cc:99`.

---

### #17. Dragonfly #6912 — Crash in rdb_save - unknown encoding for type 17
**Deploy: 3 | Reproduce: 2 | Combined: 5**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6912
- **Likely Fix Commit:** `ef296f099b6e210ad28f043be9d0a8cec4dc4885`

**Reproduce:**
```bash
./build/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
python3 replay_crash.py crashes 000000
# FATAL: Unknown encoding 0 for type 17 in rdb_save.cc:206
```

---

### #18. Kvrocks #3148 — `namespace set` deletes another namespace
**Deploy: 3 | Reproduce: 2 | Combined: 5**

- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/3148
- **Fix Commit:** `833ae36aa1d17e87be494724689b87e5234286ec`
- **Buggy Commit:** `833ae36aa1d17e87be494724689b87e5234286ec~1`

**Reproduce:**
```bash
redis-cli -p 6666
> NAMESPACE ADD ns1 token1
> NAMESPACE ADD ns2 token2
> NAMESPACE SET ns1 token2    # BUG: this deletes ns2!
> NAMESPACE GET *             # ns2 is gone
```

**Root Cause:** Token collision in the reverse mapping deletes the other namespace.

---

### #19. NATS Server #7817 — Messages lost with WorkQueue retention and R3
**Deploy: 2 | Reproduce: 3 | Combined: 5**

- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/7817
- **Fix PR:** [#7845](https://github.com/nats-io/nats-server/pull/7845)
- **Buggy Version:** v2.12.3, v2.12.4

**Reproduce:** Create R3 stream with work-queue retention. Publish 200 messages, don't ack every 10th. After max-deliver reached, check stream: expect 20 messages, see only 9.

---

### #20. NATS Server #7726 — Mixed wildcard/literal filter fails delivery
**Deploy: 2 | Reproduce: 3 | Combined: 5**

- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/7726
- **Fix Commit:** `6aded805ec9625b20ee50ded3b63135d5fe3d0a8`
- **Buggy Commit:** `6aded805ec9625b20ee50ded3b63135d5fe3d0a8~1`

**Reproduce:** Create consumer with mixed filters `--filter "events.specific" --filter "events.*"`. Publish to literal subject. Consumer fails to deliver.

---

### #21. etcd #20655 — Fast watch creation breaks reliable watch guarantee
**Deploy: 2 | Reproduce: 3 | Combined: 5**

- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/20655
- **Severity:** Critical-urgent
- **Buggy Branch:** main, release-3.5, release-3.4

**Reproduce:** Run reproduction test from PR #20654. Create watches at high frequency while writing data. Observe missed watch events.

---

### #22. etcd #20704 — Linearizability bugs in client/v3/leasing cache
**Deploy: 2 | Reproduce: 3 | Combined: 5**

- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/20704

**Reproduce:** Run the test cases from the issue: concurrent Delete+Put → Get returns deleted key's value; concurrent Put+Get → stale read.

---

### #23. hashicorp/raft #358 — Snapshot deletes negative log range
**Deploy: 3 | Reproduce: 2 | Combined: 5**

- **Language:** Go
- **Issue:** https://github.com/hashicorp/raft/issues/358
- **Fix Commit:** `7b09f38f739f486a692096c35236c7eef094e933`
- **Buggy Commit:** `7b09f38f739f486a692096c35236c7eef094e933~1`

**Reproduce:** Run Raft cluster, trigger snapshots. Observe log "Compacting logs from 26108 to 6079" (max < min).

**Root Cause:** No bounds check at `snapshot.go:231-235` before calling `DeleteRange`.

---

### #24. ClickHouse #92375 — Incorrect DISTINCT over distributed table
**Deploy: 5 | Reproduce: 1 | Combined: 6**

- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/92375

**Reproduce:**
```sql
CREATE TABLE data_local ENGINE=Memory() AS SELECT * FROM numbers(2);
CREATE TABLE data_distributed AS data_local
  ENGINE=Distributed(test_cluster_two_shards, currentDatabase(), data_local, number);
SELECT count() FROM (SELECT DISTINCT number FROM data_distributed) SETTINGS optimize_skip_unused_shards=0;  -- 2
SELECT count() FROM (SELECT DISTINCT number FROM data_distributed) SETTINGS optimize_skip_unused_shards=1;  -- 4 (WRONG!)
```

---

### #25. ClickHouse #99109 — sum(Float64) non-deterministic with max_threads
**Deploy: 5 | Reproduce: 1 | Combined: 6**

- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/99109

**Reproduce:** Insert deterministic 200k rows. `SELECT sum(value) ... SETTINGS max_threads=1` vs `max_threads=8` returns different results for 78% of keys.

---

### #26. ClickHouse #43816 — Deadlock in ReplicatedMergeTreeQueue merge wait
**Deploy: 5 | Reproduce: 1 | Combined: 6**

- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/43816

**Reproduce:** Run replicated cluster under sustained write load. Merges start but never complete (progress=0). Merge threads stuck in `setActualPartName`.

---

### #27. Seastar #2202 — Cross-shard realloc shrink crashes
**Deploy: 5 | Reproduce: 1 | Combined: 6**

- **Language:** C++
- **Issue:** https://github.com/scylladb/seastar/issues/2202

**Reproduce:**
```cpp
SEASTAR_TEST_CASE(test_cross_thread_realloc) {
    void *p = malloc(100);
    auto other_shard = (this_shard_id() + 1) % smp::count;
    return smp::submit_to(other_shard, [p]{ BOOST_REQUIRE(realloc(p, 50)); });
}
// CRASHES: assertion `object_cpu_id(ptr) == cpu_id` failed
```

---

### #28. Dragonfly #6822 — 100% CPU during periodic key expiration
**Deploy: 3 | Reproduce: 3 | Combined: 6**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6822
- **Fix Commit:** `4df1a91450cd504c37bff5730944a3569996abff`
- **Buggy Commit:** `4df1a91450cd504c37bff5730944a3569996abff~1`

**Reproduce:** Load 500k+ keys with TTL. Wait for expiration. Server becomes unresponsive at 100% CPU. `PING` times out.

**Root Cause:** Expiration traversal doesn't yield to event loop.

---

### #29. Dragonfly #6738 — Blocking commands in pipeline don't flush replies
**Deploy: 3 | Reproduce: 3 | Combined: 6**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6738
- **Fix Commit:** `c4849b4d008d1dd6fd950f251cdb9a9a2e264e00`
- **Buggy Commit:** `c4849b4d008d1dd6fd950f251cdb9a9a2e264e00~1`

**Reproduce:** `BRPOPLPUSH mylist dest 5` in one client. `EVAL "redis.call('RPUSH', 'mylist', 'val')" 0` in another. Consumer waits full 5s instead of waking immediately.

---

### #30. Dragonfly #6687 — Replica sync retry loop from unknown RDB encoding
**Deploy: 3 | Reproduce: 3 | Combined: 6**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6687
- **Fix Commit:** `8347cd80192a7be967a3983a6a55a10525915015`
- **Buggy Commit:** `8347cd80192a7be967a3983a6a55a10525915015~1`

**Reproduce:** Run Dragonfly cluster with tiered storage. Load Redis 6 RDB backup. Replicas fail with "Unknown RDB string encoding 62" and retry in a loop.

---

### #31. Kvrocks #3356 — Replication feed thread blocks, WAL exhaustion
**Deploy: 3 | Reproduce: 3 | Combined: 6**

- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/3356
- **Fix Commit:** `559a667bef223a07fea350a27168e91fe0a74601`
- **Buggy Commit:** `559a667bef223a07fea350a27168e91fe0a74601~1`

**Reproduce:** Set up master-replica. Slow the replica (network throttling). Write at high rate. WAL grows unbounded as feed thread blocks on slow consumer.

---

### #32. Kvrocks #3339 — XREADGROUP BLOCK sends double response
**Deploy: 3 | Reproduce: 3 | Combined: 6**

- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/3339
- **Fix Commit:** `25216331bce6f9e97b945aad1cbb04e2db261287`
- **Buggy Commit:** `25216331bce6f9e97b945aad1cbb04e2db261287~1`

**Reproduce:** Create stream + consumer group. Run parallel XREADGROUP BLOCK clients. Concurrently XADD. Under load, clients receive double response `*-1\r\n*0\r\n`.

---

### #33. hashicorp/raft #212 — Out-of-date followers stuck in snapshot install loop
**Deploy: 3 | Reproduce: 3 | Combined: 6**

- **Language:** Go
- **Issue:** https://github.com/hashicorp/raft/issues/212
- **Fix Commit:** `37d2320db05ca622195063977ff5d4fbe0cd8ed8`
- **Buggy Commit:** `37d2320db05ca622195063977ff5d4fbe0cd8ed8~1`

**Reproduce:** 3-node cluster → write enough to trigger compaction → force snapshot → stop follower → write more → bring follower back. Stuck loop: "Failed to install snapshot ... broken pipe".

---

### #34. hashicorp/raft #291 — Node failure triggers OOM via verifyLeader leak
**Deploy: 3 | Reproduce: 3 | Combined: 6**

- **Language:** Go
- **Issue:** https://github.com/hashicorp/raft/issues/291
- **Fix Commit:** `da92cfe76e0c1c9b94bbc9d884ec4b2b3b90b699`
- **Buggy Commit:** `da92cfe76e0c1c9b94bbc9d884ec4b2b3b90b699~1`

**Reproduce:** 3-node cluster, stop one follower, repeatedly call `VerifyLeader()`. Memory grows to 278MB+ and eventually OOM.

---

### #35. CockroachDB #166122 — Partial index data loss during concurrent update
**Deploy: 3 | Reproduce: 3 | Combined: 6**

- **Language:** Go
- **Issue:** https://github.com/cockroachdb/cockroach/issues/166122
- **Fix Commit:** `8c90d1ad0b59f18926d3b77f9f653d942f755e36`
- **Buggy Commit:** `8c90d1ad0b59f18926d3b77f9f653d942f755e36~1`

**Reproduce:** Full reproduction gist: https://gist.github.com/fqazi/20467eaa1046a1e31082ece6a84a36ae

---

### #36. NATS Server #7718 — Subscription leak with OrderedConsumer churn
**Deploy: 2 | Reproduce: 4 | Combined: 6**

- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/7718
- **Fix Commit:** `b72becc443073300e5599d06fa0cde1cd5518589`
- **Buggy Commit:** `b72becc443073300e5599d06fa0cde1cd5518589~1`

**Reproduce:** NATS cluster with overlapping stream imports. Rapidly create/destroy OrderedConsumers. Subscription count grows unboundedly.

---

### #37. NATS Server #6888 — JetStream stream lost after kill -9
**Deploy: 2 | Reproduce: 4 | Combined: 6**

- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/6888
- **Buggy Version:** v2.10.20

**Reproduce:** 3-node cluster, R3 stream. `kill -9` a few processes, restart. `getStreamNames()` returns empty — stream is GONE. Jepsen test: https://github.com/jepsen-io/nats

---

### #38. ClickHouse #75699 — Logical error in JOIN Merge table over Distributed
**Deploy: 5 | Reproduce: 2 | Combined: 7**

- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/75699
- **Fix Commit:** `9334d08f0c942a7402e88f3929f3252eb032722d`
- **Buggy Commit:** `9334d08f0c942a7402e88f3929f3252eb032722d~1`

**Reproduce:**
```sql
CREATE TABLE a (key UInt32) ENGINE = MergeTree ORDER BY key;
CREATE TABLE b (key UInt32, ID UInt32) ENGINE = MergeTree ORDER BY key;
CREATE TABLE aa ENGINE = Distributed(test_cluster_two_shards, currentDatabase(), a, key);
CREATE TABLE m ENGINE = Merge(currentDatabase(), 'a');
INSERT INTO a VALUES (0); INSERT INTO b VALUES (0, 1), (42, 1);
SELECT * FROM m INNER JOIN b USING(key) WHERE ID = 1;
-- LOGICAL_ERROR: Column ID does not have valid source node
```

---

### #39. ClickHouse #78074 — Invalid rows in Chunk with distributed table
**Deploy: 5 | Reproduce: 2 | Combined: 7**

- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/78074
- **Fix Commit:** `1b768fe2b4695dbb5d6b7534fe881e812852cb45`
- **Buggy Commit:** `1b768fe2b4695dbb5d6b7534fe881e812852cb45~1`

**Reproduce:** Distributed table with LowCardinality column, JOIN with `join_to_sort_minimum_perkey_rows = 0`. Triggers LOGICAL_ERROR.

---

### #40. ClickHouse #29332 — Predicate pushdown wrong with distributed IN subqueries
**Deploy: 5 | Reproduce: 2 | Combined: 7**

- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/29332

**Reproduce:** Query with IN subquery on distributed table + `enable_optimize_predicate_expression=1` incorrectly fails with `DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED`.

---

### #41. ClickHouse #40571 — Keeper crashes on every startup with segfault
**Deploy: 5 | Reproduce: 2 | Combined: 7**

- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/40571
- **Fix Commit:** `cecdcb50598aad333d8cb784b914a19a567e0b88`
- **Buggy Commit:** `cecdcb50598aad333d8cb784b914a19a567e0b88~1`

**Reproduce:** Run Keeper v22.7 standalone. Crashes during initialization with segfault 11 on every start.

---

### #42. ClickHouse #98079 — Keeper disconnects after addWatch()
**Deploy: 5 | Reproduce: 2 | Combined: 7**

- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/98079
- **Fix Commit:** `3515972fbc064f7b62c963c8e25969053a6a38c2`
- **Buggy Commit:** `3515972fbc064f7b62c963c8e25969053a6a38c2~1`

**Reproduce:** Connect Java ZooKeeper client with CuratorCache. Keeper disconnects after `addWatch()`.

---

### #43. ClickHouse #44865 — Background merges stuck on replicas
**Deploy: 5 | Reproduce: 2 | Combined: 7**

- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/44865

**Reproduce:** Replicated cluster under sustained inserts. One replica's merges stop. Needs restart to resolve. Root cause: deadlock in `MergeTreeBackgroundExecutor` (#43816).

---

### #44. Redpanda #25769 — ListOffsets returns incorrect results
**Deploy: 5 | Reproduce: 2 | Combined: 7**

- **Language:** C++
- **Issue:** https://github.com/redpanda-data/redpanda/issues/25769
- **Fix Commit:** `18b0c24d7b306add4a1390fc2c56a5de5420f567`
- **Buggy Commit:** `18b0c24d7b306add4a1390fc2c56a5de5420f567~1`

**Reproduce:** Produce compressed records with franz-go. ListOffsets returns wrong offset because `batch_timequery()` doesn't decompress.

---

### #45. ScyllaDB #27130 — Segfault on raft_topology/reload during startup
**Deploy: 7 | Reproduce: 1 | Combined: 7**

- **Language:** C++
- **Issue:** https://github.com/scylladb/scylladb/issues/27130
- **Fix Commit:** `e54abde3e851bbba8aca0a06085f234ea1f4b74a`
- **Buggy Commit:** `e54abde3e851bbba8aca0a06085f234ea1f4b74a~1`

**Reproduce:**
```bash
# Start ScyllaDB, then immediately call REST API:
for i in $(seq 1 10); do sleep 1 && curl -X POST 'http://localhost:10000/storage_service/raft_topology/reload'; done
# Segfault every time
```

---

### #46. Nomad #27567 — Scheduler panic during eval processing
**Deploy: 3 | Reproduce: 4 | Combined: 7**

- **Language:** Go
- **Issue:** https://github.com/hashicorp/nomad/issues/27567
- **Fix Commit:** `f95371693165852d0d58dca5b178a23c34d93819`
- **Buggy Commit:** `f95371693165852d0d58dca5b178a23c34d93819~1`
- **Buggy Version:** v1.11.2

**Reproduce:** Deploy system jobs with deployment configuration, trigger evaluations. Scheduler panics with nil pointer dereference.

---

### #47. hashicorp/raft #268 — Shutdown() deadlock with takeSnapshot()
**Deploy: 3 | Reproduce: 4 | Combined: 7**

- **Language:** Go
- **Issue:** https://github.com/hashicorp/raft/issues/268
- **Fix Commit:** `2e997410f28efe8106fc606d21cb655be1b05dee`
- **Buggy Commit:** `2e997410f28efe8106fc606d21cb655be1b05dee~1`

**Reproduce:** Call `Raft.Shutdown()` while `runSnapshots()` is deciding to take a snapshot. `Shutdown().Error()` hangs forever.

---

### #48. Dragonfly #6862 — Crash in db_slice during concurrent operations
**Deploy: 3 | Reproduce: 4 | Combined: 7**

- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6862

**Reproduce:** Dragonfly in cluster mode with multiple proactor threads. Concurrent writes + cluster management. Crash at `db_slice.cc:550`.

---

### #49. etcd #20657 — Race between snapshot cleanup and application
**Deploy: 2 | Reproduce: 5 | Combined: 7**

- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/20657

**Reproduce:** Multi-node cluster with `--snapshot-count=2`. Rapid leader changes + writes. Follower panics: `.snap.db` file deleted during application.

---

### #50. etcd #20269 — Panic on member rejoin after reset
**Deploy: 2 | Reproduce: 5 | Combined: 7**

- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/20269

**Reproduce:** Multi-node cluster with learner. Simulate failure, reset config, re-add. Panic: `tocommit(X) is out of range [lastIndex(0)]`.

---

### #51. etcd #20793 — Learner promotion not persisted across upgrades
**Deploy: 2 | Reproduce: 5 | Combined: 7**

- **Language:** Go
- **Issue:** https://github.com/etcd-io/etcd/issues/20793
- **Fix Commit:** `2e24a9845a3cd24fb52d676670e66c697f34336d`
- **Buggy Commit:** `2e24a9845a3cd24fb52d676670e66c697f34336d~1`

**Reproduce:** Use [upgradeDemo tool](https://github.com/ahrtr/etcd-issues/tree/master/etcd/upgradeDemo). Upgrade 3.5.19 → 3.5.21 → 3.6.4. Final upgrade fails: "too many learner members".

---

### #52. NATS Server #7852 — Subject filtering performance degradation
**Deploy: 2 | Reproduce: 5 | Combined: 7**

- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/7852
- **Fix Commit:** `66e9bbc7f8684dd1b31c54ef686924e0841f9846`
- **Buggy Commit:** `66e9bbc7f8684dd1b31c54ef686924e0841f9846~1`

**Reproduce:** Consumer with FilterSubjects matching all subjects shows >20% performance degradation vs no filter.

---

### #53. Redpanda #15118 — Future assert under load in kafka client
**Deploy: 5 | Reproduce: 3 | Combined: 8**

- **Language:** C++
- **Issue:** https://github.com/redpanda-data/redpanda/issues/15118
- **Fix Commit:** `6cd0e7054aada957dc28b6826b6f4f77ea6eb40e`
- **Buggy Commit:** `6cd0e7054aada957dc28b6826b6f4f77ea6eb40e~1`

**Reproduce:** Run Redpanda under sustained Kafka client load. `ss::future` assert triggers when authentication fails during broker stop.

---

### #54. Redpanda #16944 — Oversized allocation in raft::replicate_batcher
**Deploy: 5 | Reproduce: 3 | Combined: 8**

- **Language:** C++
- **Issue:** https://github.com/redpanda-data/redpanda/issues/16944
- **Fix Commit:** `952b8c96298380b5986e4dfe71dba5616a2495b3`
- **Buggy Commit:** `952b8c96298380b5986e4dfe71dba5616a2495b3~1`

**Reproduce:** High write throughput. Oversized allocation (262144 bytes) in `raft::replicate_batcher::flush`.

---

### #55. ScyllaDB #28200 — Use-after-free in streaming_task_impl::run
**Deploy: 7 | Reproduce: 1 | Combined: 8**

- **Language:** C++
- **Issue:** https://github.com/scylladb/scylladb/issues/28200

**Reproduce:** Trigger topology change with streaming (node join/decommission). `coroutine::lambda` holds pointer to destroyed lambda. Build with ASAN to detect.

---

### #56. ScyllaDB #25173 — Truncate check exits raft applier fiber permanently
**Deploy: 7 | Reproduce: 1 | Combined: 8**

- **Language:** C++
- **Issue:** https://github.com/scylladb/scylladb/issues/25173
- **Fix Commit:** `bb922b2aa9dd58de902848d99fde06b9b1c5828a`
- **Buggy Commit:** `bb922b2aa9dd58de902848d99fde06b9b1c5828a~1`

**Reproduce:** Write data concurrently while DROP TABLE/KEYSPACE executes. Internal error exits raft applier fiber. Node permanently cannot execute raft commands.

---

### #57. RocksDB #10751 — Stalled writes block forever during shutdown
**Deploy: 3 | Reproduce: 5 | Combined: 8**

- **Language:** C++
- **Issue:** https://github.com/facebook/rocksdb/issues/10751
- **Fix Commit:** `a45e6878f39cdc777c54e5d6749d53c1f70e2b52`
- **Buggy Commit:** `a45e6878f39cdc777c54e5d6749d53c1f70e2b52~1`

**Reproduce:** Open RocksDB with write rate limiter. Put enough data to trigger stalls. Call `DB::Close()` while writes are stalled. Close blocks forever.

---

### #58. RocksDB #13652 — ExportColumnFamily misses committed data
**Deploy: 3 | Reproduce: 5 | Combined: 8**

- **Language:** C++
- **Issue:** https://github.com/facebook/rocksdb/issues/13652
- **Fix Commit:** `25d8a6b0b5ccde1b7d26920a264ebc7f810ee1b5`
- **Buggy Commit:** `25d8a6b0b5ccde1b7d26920a264ebc7f810ee1b5~1`

**Reproduce:** Write + flush to column family. Call `Checkpoint::ExportColumnFamily`. Occasionally export misses committed data.

---

### #59. ScyllaDB #28057 — Raft topology IP->ID mapping lost on restart
**Deploy: 7 | Reproduce: 2 | Combined: 9**

- **Language:** C++
- **Issue:** https://github.com/scylladb/scylladb/issues/28057
- **Fix Commit:** `af6cb0d0a431170d32ad7816c050f875298aa840`
- **Buggy Commit:** `af6cb0d0a431170d32ad7816c050f875298aa840~1`

**Reproduce:** Node replace fails during streaming. All live nodes shut down before rollback. Restart all. `nodetool status` hits internal error for replacing node's IP.

---

### #60. ScyllaDB #27956 — Staging SSTables not discovered causing view inconsistency
**Deploy: 7 | Reproduce: 2 | Combined: 9**

- **Language:** C++
- **Issue:** https://github.com/scylladb/scylladb/issues/27956
- **Buggy Commit:** `5d1f74b86ac6ef151871ee300f8728` (regression point)

**Reproduce:** Force view update failure. Restart node. Staging SSTables never processed. Base table and materialized view permanently inconsistent.

---

## Summary

### By Language
| Language | Count | Systems |
|----------|-------|---------|
| C++ | 40 | Dragonfly (19), ClickHouse (8), Kvrocks (4), Seastar (1), ScyllaDB (4), Redpanda (3), RocksDB (2) |
| Go | 20 | etcd (7), NATS (6), hashicorp/raft (3), CockroachDB (1), Nomad (1) |

### By Project
| Project | Lang | Deploy | Bugs | Fix Commits |
|---------|------|--------|------|-------------|
| Dragonfly | C++ | 3 | 19 | 18/19 |
| ClickHouse | C++ | 5 | 8 | 6/8 |
| etcd | Go | 2 | 7 | 4/7 |
| NATS | Go | 2 | 6 | 5/6 |
| Kvrocks | C++ | 3 | 4 | 4/4 |
| hashicorp/raft | Go | 3 | 3 | 3/3 |
| ScyllaDB | C++ | 7 | 4 | 3/4 |
| Redpanda | C++ | 5 | 3 | 3/3 |
| RocksDB | C++ | 3 | 2 | 2/2 |
| CockroachDB | Go | 3 | 1 | 1/1 |
| Nomad | Go | 3 | 1 | 1/1 |
| Seastar | C++ | 5 | 1 | 0/1 |

### Recommended Evaluation Order

**Phase 1: Quick wins (score 4-5)** — Bugs #1–#23
Dragonfly crashes (replay scripts), Kvrocks crashes (one-liner Redis commands), NATS consumer bugs, etcd learner/race issues. Setup and trigger in minutes.

**Phase 2: Medium effort (score 6)** — Bugs #24–#37
ClickHouse SQL-reproducible bugs, Dragonfly liveness/replication, Kvrocks replication, hashicorp/raft OOM/stuck followers, CockroachDB data loss.

**Phase 3: Deeper investigation (score 7-9)** — Bugs #38–#60
ClickHouse Keeper/distributed, Redpanda Kafka compat, ScyllaDB raft topology, RocksDB shutdown/export, etcd upgrade/snapshot races.

### Ideal First 5 Test Cases
1. **Dragonfly #6753** (C++, score 4) — `redis-cli DEBUG POPULATE 100 prefix 0` → instant SIGFPE
2. **Kvrocks #3315** (C++, score 4) — `redis-cli ZDIFF 0 a` → instant crash
3. **NATS #7760** (Go, score 4) — consumer filter + step-down → silent message loss
4. **etcd #20893** (Go, score 4) — `--force-new-cluster` leaves learner → deterministic
5. **ClickHouse #92375** (C++, score 6) — SQL copy-paste → wrong DISTINCT result
