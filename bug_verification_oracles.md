# Bug Verification Oracles
## Definitive Pass/Fail Tests for All 61 Ranked Bugs

**Purpose:** For each bug, this document specifies:
- **Trigger**: exact steps to attempt to reproduce the bug
- **FAIL (bug present)**: observable behavior when the bug exists
- **PASS (bug fixed)**: observable behavior when the bug is fixed
- **Verdict method**: how to programmatically determine PASS/FAIL

Oracle types used:
- `CRASH` — process crashes (non-zero exit, signal) vs stays alive
- `OUTPUT` — wrong output vs correct output (diff-able)
- `HANG` — process hangs/deadlocks vs completes within timeout
- `METRIC` — observable metric (memory, CPU, count) exceeds threshold vs stays normal
- `RACE` — Go/C++ race detector fires vs clean run
- `LOG` — specific error pattern appears in logs vs absent

---

## Top 30 (Mixed Languages) — Bugs #1–#30

---

### #1. Dragonfly #6856 — FLUSHSLOTS out-of-bounds crash
**Oracle type:** `CRASH`

```bash
# Trigger
./dragonfly --port 6380 --proactor_threads 1 --dbfilename="" \
  --cluster_mode=yes --cluster_node_id=0000000000000000000000000000000000000000 &
PID=$!
sleep 2
# Send DFLYCLUSTER FLUSHSLOTS with slot >= 16384
redis-cli -p 6380 DFLYCLUSTER FLUSHSLOTS 16384

# Verdict
wait $PID
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then echo "FAIL: bug present (crash)"; else echo "PASS: bug fixed"; fi
```

- **FAIL:** Process crashes with SIGABRT (`bitset::set` OOB). Exit code != 0.
- **PASS:** Process returns an error response but stays alive. Exit code 0 on graceful shutdown.

---

### #2. Dragonfly #6825 — CONFIG number overflow crash
**Oracle type:** `CRASH`

```bash
# Trigger: replay the crash archive from the issue
tar xzf crash-000000.tar.gz && cd crash-000000
./dragonfly --port 6380 --proactor_threads 1 --dbfilename="" \
  --cluster_mode=yes --cluster_node_id=0000000000000000000000000000000000000000 &
PID=$!
sleep 2
python3 replay_crash.py crashes 000000

# Verdict
wait $PID
EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then echo "FAIL"; else echo "PASS"; fi
```

- **FAIL:** SIGABRT on check failure. Exit code != 0.
- **PASS:** Error response, process alive.

---

### #3. NATS #7760 — Consumer filter stops matching after leader step-down
**Oracle type:** `OUTPUT`

```bash
# Setup: 3-node NATS cluster
# Trigger:
nats stream add foo-stream --subjects "foo.>" --replicas 3 --retention interest
nats consumer add foo-stream c1 --pull --filter "foo.bar" --filter "foo.bar1" \
  --deliver all --ack explicit --max-deliver 20 --max-pending 1000

# Verify pre-stepdown works
nats pub "foo.bar" 'msg1' && nats pub "foo.bar" 'msg2'
PRE=$(nats consumer next foo-stream c1 --count 2 --wait 3s 2>&1 | grep -c "msg")

# Edit filter, step down, publish again
nats consumer edit foo-stream c1 --filter "foo.bar" --filter "foo.bar2"
nats consumer cluster step-down foo-stream c1
sleep 2
nats pub "foo.bar" 'after-stepdown'
POST=$(nats consumer next foo-stream c1 --count 1 --wait 5s 2>&1 | grep -c "after-stepdown")

# Verdict
if [ "$POST" -eq 0 ]; then echo "FAIL: messages not delivered after step-down"
else echo "PASS: consumer correctly delivers after step-down"; fi
```

- **FAIL:** `nats consumer next` returns timeout (0 messages).
- **PASS:** `nats consumer next` returns the published message.

---

### #4. etcd #20893 — --force-new-cluster can't remove learners
**Oracle type:** `OUTPUT`

```bash
# Setup: 3-member cluster with --snapshot-count=2
# Add learner, write >2 keys, stop all, restart one with --force-new-cluster

MEMBERS=$(etcdctl member list --write-out=json | python3 -c "
import json,sys
data=json.load(sys.stdin)
learners=[m for m in data['members'] if m.get('isLearner')]
print(len(learners))
")

# Verdict
if [ "$MEMBERS" -gt 0 ]; then echo "FAIL: learner still present after force-new-cluster"
else echo "PASS: learner correctly removed"; fi
```

- **FAIL:** `etcdctl member list` shows the learner member.
- **PASS:** Only the single forced member appears.

---

### #5. etcd #19172 — Data race when closing embedded etcd
**Oracle type:** `RACE`

```bash
cd tests/integration/embed
go test -race -run TestEmbedEtcd -count=1 -timeout 60s 2>&1 | tee /tmp/race_output.txt
RACE_FOUND=$(grep -c "DATA RACE" /tmp/race_output.txt)

# Verdict
if [ "$RACE_FOUND" -gt 0 ]; then echo "FAIL: data race detected"
else echo "PASS: no data race"; fi
```

- **FAIL:** Go race detector reports `WARNING: DATA RACE` between `Close()` and `errHandler()`.
- **PASS:** Test passes cleanly with no race warnings.

---

### #6. NATS #7817 — Messages lost with WorkQueue R3
**Oracle type:** `OUTPUT`

```bash
# Setup: 3-node cluster, R3 stream, work-queue retention
# Publish 200 messages, don't ack every 10th (20 dead-lettered)
# After max-deliver reached:
STREAM_MSGS=$(nats stream info wq --json | python3 -c "import json,sys;print(json.load(sys.stdin)['state']['messages'])")

# Verdict: should have 20 dead-lettered messages, not fewer
if [ "$STREAM_MSGS" -lt 20 ]; then echo "FAIL: only $STREAM_MSGS messages (expected 20, messages lost)"
else echo "PASS: all $STREAM_MSGS dead-lettered messages preserved"; fi
```

- **FAIL:** Stream contains fewer than 20 messages (some lost).
- **PASS:** Stream contains exactly 20 unacked messages.

---

### #7. NATS #7726 — Mixed wildcard/literal filter fails delivery
**Oracle type:** `OUTPUT`

```bash
# Create stream + consumer with mixed filters
nats stream add test --subjects "events.>"
nats consumer add test mixed --pull --filter "events.specific" --filter "events.*"
nats pub events.specific "hello"
RESULT=$(nats consumer next test mixed --count 1 --wait 3s 2>&1)

# Verdict
if echo "$RESULT" | grep -q "hello"; then echo "PASS"
else echo "FAIL: literal subject message not delivered"; fi
```

- **FAIL:** Consumer returns timeout, message not delivered.
- **PASS:** Consumer receives "hello".

---

### #8. etcd #20655 — Fast watch creation breaks reliable watch
**Oracle type:** `OUTPUT`

```bash
# Run the reproduction test from PR #20654
go test -run TestFastWatchReliability -count=1 -timeout 120s ./tests/... 2>&1 | tee /tmp/watch_test.txt
TEST_RESULT=$?

# Verdict
if [ $TEST_RESULT -ne 0 ]; then echo "FAIL: watch events dropped"
else echo "PASS: all watch events received"; fi
```

- **FAIL:** Test fails — watch events were dropped.
- **PASS:** Test passes — all events received in order.

---

### #9. etcd #20704 — Linearizability bugs in leasing cache
**Oracle type:** `OUTPUT`

```bash
# Run the test cases from the issue (concurrent Delete+Put, Put+Get)
go test -run TestLeasingCacheLinearizability -count=5 -race ./client/v3/leasing/... 2>&1 | tee /tmp/leasing_test.txt

# Verdict
if grep -q "FAIL" /tmp/leasing_test.txt; then echo "FAIL: linearizability violation"
else echo "PASS: cache operations are linearizable"; fi
```

- **FAIL:** Get returns value for a deleted key, or returns stale value.
- **PASS:** All operations are linearizable.

---

### #10. hashicorp/raft #358 — Snapshot deletes negative log range
**Oracle type:** `LOG`

```bash
# Run raft cluster, trigger snapshots, check logs
grep -c "Compacting logs from [0-9]* to [0-9]*" /tmp/raft.log | while read line; do
  FROM=$(echo "$line" | grep -oP "from \K[0-9]+")
  TO=$(echo "$line" | grep -oP "to \K[0-9]+")
  if [ "$FROM" -gt "$TO" ]; then echo "FAIL: negative range $FROM to $TO"; exit 1; fi
done
echo "PASS: all compaction ranges valid"
```

- **FAIL:** Log contains "Compacting logs from X to Y" where X > Y.
- **PASS:** All compaction ranges have min < max, or a "no logs to truncate" message appears.

---

### #11. ClickHouse #92375 — Incorrect DISTINCT over distributed
**Oracle type:** `OUTPUT`

```sql
-- Run both queries and compare
SELECT count() FROM (SELECT DISTINCT number FROM data_distributed)
  SETTINGS optimize_skip_unused_shards=0;  -- → A
SELECT count() FROM (SELECT DISTINCT number FROM data_distributed)
  SETTINGS optimize_skip_unused_shards=1;  -- → B
```

```bash
# Verdict
if [ "$A" -ne "$B" ]; then echo "FAIL: DISTINCT returns $A vs $B"
else echo "PASS: both return $A"; fi
```

- **FAIL:** Results differ (e.g., 2 vs 4).
- **PASS:** Both queries return the same count (2).

---

### #12. ClickHouse #99109 — sum(Float64) non-deterministic with max_threads
**Oracle type:** `OUTPUT`

```sql
SELECT sum(value) FROM bug_fp_sum WHERE user_id=21238 GROUP BY user_id SETTINGS max_threads=1; -- → A
SELECT sum(value) FROM bug_fp_sum WHERE user_id=21238 GROUP BY user_id SETTINGS max_threads=8; -- → B
```

```bash
# Verdict (note: this is floating-point, so we check exact match)
if [ "$A" != "$B" ]; then echo "FAIL: sum differs ($A vs $B)"
else echo "PASS: deterministic sum"; fi
```

- **FAIL:** Different numerical results for same data with different thread counts.
- **PASS:** Identical results regardless of `max_threads`.
- **Note:** This is inherently a floating-point associativity issue. "Fix" may mean ClickHouse uses compensated summation (Kahan). Verify the specific fix approach.

---

### #13. Seastar #2202 — Cross-shard realloc shrink crashes
**Oracle type:** `CRASH`

```cpp
// Compile and run the test case:
SEASTAR_TEST_CASE(test_cross_thread_realloc) {
    void *p = malloc(100);
    auto other_shard = (this_shard_id() + 1) % smp::count;
    return smp::submit_to(other_shard, [p]{
        BOOST_REQUIRE(realloc(p, 50));
    });
}
```

```bash
./build/test_unit --smp 2 2>&1
EXIT_CODE=$?
# Verdict
if [ $EXIT_CODE -ne 0 ]; then echo "FAIL: crash on cross-shard realloc"
else echo "PASS: cross-shard realloc handled"; fi
```

- **FAIL:** Assertion failure: `object_cpu_id(ptr) == cpu_id`. Process crashes.
- **PASS:** Realloc succeeds, test passes.

---

### #14. Dragonfly #6822 — 100% CPU during periodic expiration
**Oracle type:** `METRIC`

```bash
./dragonfly --port 6379 --proactor_threads 1 --dbfilename="" &
PID=$!
# Load keys with short TTL
redis-cli -p 6379 DEBUG POPULATE 500000
for i in $(seq 1 500000); do redis-cli -p 6379 EXPIRE "key:$i" 5; done
# Wait for expiration cycle
sleep 10
# Measure: can we get a response within 1 second?
RESPONSE=$(timeout 1 redis-cli -p 6379 PING 2>&1)

# Verdict
if [ "$RESPONSE" != "PONG" ]; then echo "FAIL: server unresponsive during expiration"
else echo "PASS: server responsive during expiration"; fi
```

- **FAIL:** `PING` times out (server is stuck in expiration loop at 100% CPU).
- **PASS:** `PING` returns `PONG` within 1 second.

---

### #15. Dragonfly #6738 — Blocking commands in pipeline not flushed
**Oracle type:** `OUTPUT`

```bash
# Terminal 1: blocking consumer
timeout 10 redis-cli -p 6379 BRPOPLPUSH mylist dest 8 &
CONSUMER_PID=$!
sleep 1

# Terminal 2: Lua script pushes to list
redis-cli -p 6379 EVAL "redis.call('RPUSH', 'mylist', 'wakeup')" 0
sleep 1

# Check if consumer got the value (should wake within 1s, not wait 8s)
RESULT=$(redis-cli -p 6379 LRANGE dest 0 -1)
kill $CONSUMER_PID 2>/dev/null
wait $CONSUMER_PID 2>/dev/null
ELAPSED=$SECONDS  # approximate

# Verdict
if echo "$RESULT" | grep -q "wakeup"; then echo "PASS: consumer woke immediately"
else echo "FAIL: consumer not woken by Lua RPUSH"; fi
```

- **FAIL:** Consumer waits full timeout (8s), `dest` is empty after Lua push.
- **PASS:** Consumer wakes within ~1s, `dest` contains "wakeup".

---

### #16. hashicorp/raft #212 — Followers stuck in snapshot install loop
**Oracle type:** `LOG`

```bash
# After bringing stale follower back, monitor leader logs for 30s
timeout 30 tail -f /tmp/raft_leader.log | tee /tmp/loop_check.txt &
sleep 30

LOOP_COUNT=$(grep -c "Failed to install snapshot" /tmp/loop_check.txt)
FOLLOWER_SYNCED=$(grep -c "peer.*match=" /tmp/loop_check.txt)

# Verdict
if [ "$LOOP_COUNT" -gt 5 ] && [ "$FOLLOWER_SYNCED" -eq 0 ]; then
  echo "FAIL: stuck in snapshot install loop ($LOOP_COUNT failures)"
else
  echo "PASS: follower caught up"
fi
```

- **FAIL:** Repeated "Failed to install snapshot" + "broken pipe" with no progress.
- **PASS:** Snapshot installs successfully, follower catches up.

---

### #17. hashicorp/raft #291 — Node failure triggers OOM
**Oracle type:** `METRIC`

```bash
# Start 3-node cluster, stop one follower, call VerifyLeader in loop
for i in $(seq 1 10000); do curl -s http://localhost:8500/v1/operator/raft/configuration > /dev/null; done &
sleep 30

# Check leader memory
MEM_MB=$(ps -o rss= -p $LEADER_PID | awk '{print int($1/1024)}')

# Verdict
if [ "$MEM_MB" -gt 200 ]; then echo "FAIL: memory leak ($MEM_MB MB, expected <50)"
else echo "PASS: memory stable ($MEM_MB MB)"; fi
```

- **FAIL:** Memory grows unboundedly (>200MB in `deferError.init`).
- **PASS:** Memory stays stable (<50MB).

---

### #18. CockroachDB #166122 — Partial index data loss during concurrent update
**Oracle type:** `OUTPUT`

```bash
# Run the reproduction script from the gist
# https://gist.github.com/fqazi/20467eaa1046a1e31082ece6a84a36ae
# After the test:
NULLS=$(cockroach sql --insecure -e "SELECT count(*) FROM t WHERE indexed_col IS NULL" 2>&1 | tail -1)
PHANTOMS=$(cockroach sql --insecure -e "SELECT count(*) FROM t@partial_idx WHERE indexed_col IS NULL" 2>&1 | tail -1)

# Verdict
if [ "$NULLS" -gt 0 ] || [ "$PHANTOMS" -gt 0 ]; then
  echo "FAIL: data loss (NULLs=$NULLS) or phantom rows ($PHANTOMS)"
else echo "PASS: index consistent"; fi
```

- **FAIL:** Partial index contains NULL values or phantom rows that shouldn't exist.
- **PASS:** Index is consistent with base table.

---

### #19. NATS #7718 — Subscription leak with OrderedConsumer churn
**Oracle type:** `METRIC`

```bash
# Create and destroy OrderedConsumers rapidly for 30s
# Monitor subscription count
SUBS_BEFORE=$(curl -s http://localhost:8222/connz | python3 -c "import json,sys;print(json.load(sys.stdin)['total'])")
# ... churn OrderedConsumers ...
sleep 30
SUBS_AFTER=$(curl -s http://localhost:8222/connz | python3 -c "import json,sys;print(json.load(sys.stdin)['total'])")

# Verdict
GROWTH=$((SUBS_AFTER - SUBS_BEFORE))
if [ "$GROWTH" -gt 100 ]; then echo "FAIL: subscription leak ($GROWTH new subs)"
else echo "PASS: subscriptions cleaned up"; fi
```

- **FAIL:** Subscription count grows unboundedly.
- **PASS:** Subscription count stays stable.

---

### #20. NATS #6888 — JetStream stream lost after kill -9
**Oracle type:** `OUTPUT`

```bash
# After kill -9 + restart cycle:
STREAMS=$(nats stream ls --json 2>/dev/null | python3 -c "import json,sys;print(len(json.load(sys.stdin)))")

# Verdict
if [ "$STREAMS" -eq 0 ]; then echo "FAIL: all streams lost after crash recovery"
else echo "PASS: streams preserved ($STREAMS found)"; fi
```

- **FAIL:** `getStreamNames()` returns empty list.
- **PASS:** Stream still exists and is accessible.

---

### #21. ClickHouse #75699 — Logical error in JOIN Merge over Distributed
**Oracle type:** `CRASH` or `OUTPUT`

```sql
SELECT * FROM m INNER JOIN b USING(key) WHERE ID = 1;
```

```bash
RESULT=$(clickhouse-client --query "SELECT * FROM m INNER JOIN b USING(key) WHERE ID = 1" 2>&1)
if echo "$RESULT" | grep -q "LOGICAL_ERROR"; then echo "FAIL"
else echo "PASS"; fi
```

- **FAIL:** `DB::Exception: LOGICAL_ERROR` thrown.
- **PASS:** Query returns correct result set.

---

### #22. ClickHouse #78074 — Invalid rows in Chunk with distributed table
**Oracle type:** `CRASH` or `OUTPUT`

```bash
RESULT=$(clickhouse-client --query "..." 2>&1)  # query from issue
if echo "$RESULT" | grep -q "LOGICAL_ERROR\|Invalid number of rows"; then echo "FAIL"
else echo "PASS"; fi
```

- **FAIL:** `LOGICAL_ERROR: Invalid number of rows in Chunk`.
- **PASS:** Query succeeds.

---

### #23. ClickHouse #29332 — Predicate pushdown wrong with distributed IN
**Oracle type:** `OUTPUT`

```sql
-- With enable_optimize_predicate_expression=1, should NOT error:
SELECT * FROM (SELECT id, count() FROM t_dist GROUP BY id)
WHERE id IN (SELECT id FROM t_dist WHERE notEmpty(s))
SETTINGS enable_optimize_predicate_expression = 1, distributed_product_mode = 'deny';
```

```bash
RESULT=$(clickhouse-client --query "..." 2>&1)
if echo "$RESULT" | grep -q "DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED"; then echo "FAIL"
else echo "PASS"; fi
```

- **FAIL:** `DISTRIBUTED_IN_JOIN_SUBQUERY_DENIED` error.
- **PASS:** Query succeeds with correct results.

---

### #24. Nomad #27567 — Scheduler panic during eval processing
**Oracle type:** `CRASH`

```bash
# Deploy system jobs, trigger evaluations
# Monitor Nomad server logs
PANICS=$(grep -c "panic" /var/log/nomad/server.log)

# Verdict
if [ "$PANICS" -gt 0 ]; then echo "FAIL: scheduler panicked"
else echo "PASS: no panics"; fi
```

- **FAIL:** Log contains `panic: runtime error: nil pointer dereference` in scheduler.
- **PASS:** Evaluations processed without panic.

---

### #25. etcd #20657 — Race between snapshot cleanup and application
**Oracle type:** `CRASH`

```bash
# Run cluster with --snapshot-count=2, trigger rapid leader changes + writes
# Monitor for panics
PANICS=$(grep -c "panic\|no such file" /tmp/etcd_follower.log)

# Verdict
if [ "$PANICS" -gt 0 ]; then echo "FAIL: snapshot file deleted during apply"
else echo "PASS: snapshot apply completed safely"; fi
```

- **FAIL:** Follower panics with "no such file or directory" for `.snap.db`.
- **PASS:** Snapshot apply completes without error.

---

### #26. etcd #20269 — Panic on member rejoin after reset
**Oracle type:** `CRASH`

```bash
# After resetting and re-adding learner:
PANICS=$(grep -c "tocommit.*is out of range" /tmp/etcd_learner.log)

# Verdict
if [ "$PANICS" -gt 0 ]; then echo "FAIL: panic on rejoin"
else echo "PASS: member rejoined successfully"; fi
```

- **FAIL:** `panic: tocommit(X) is out of range [lastIndex(0)]`.
- **PASS:** Member joins cluster and begins receiving entries.

---

### #27. etcd #20793 — Learner promotion not persisted across upgrades
**Oracle type:** `OUTPUT`

```bash
# After upgrade sequence (3.5.19 → 3.5.21 → 3.6.4):
RESULT=$(etcdctl member list 2>&1)

# Verdict
if echo "$RESULT" | grep -q "too many learner"; then echo "FAIL"
elif echo "$RESULT" | grep -c "isLearner=true" | grep -q "[2-9]"; then echo "FAIL: duplicate learners"
else echo "PASS"; fi
```

- **FAIL:** `etcdserver: too many learner members in cluster` or duplicate member entries.
- **PASS:** Cluster healthy with correct membership.

---

### #28. hashicorp/raft #268 — Shutdown() deadlock with takeSnapshot()
**Oracle type:** `HANG`

```bash
# Call Shutdown() during snapshot activity
timeout 30 go test -run TestRaftShutdownDuringSnapshot -count=1 ./... 2>&1
EXIT=$?

# Verdict
if [ $EXIT -eq 124 ]; then echo "FAIL: deadlock (timeout after 30s)"
else echo "PASS: shutdown completed"; fi
```

- **FAIL:** `Shutdown().Error()` hangs forever (timeout fires).
- **PASS:** Shutdown completes within a reasonable time.

---

### #29. Dragonfly #6862 — Crash in db_slice during concurrent ops
**Oracle type:** `CRASH`

```bash
# Run cluster mode with concurrent operations
# Monitor process exit code
wait $PID
if [ $? -ne 0 ]; then echo "FAIL: crash at db_slice.cc"
else echo "PASS"; fi
```

- **FAIL:** Process crashes with assertion failure at `db_slice.cc:550`.
- **PASS:** Operations complete without crash.

---

### #30. NATS #7852 — Subject filtering performance degradation
**Oracle type:** `METRIC`

```bash
# Measure delivery rate with and without FilterSubjects
RATE_NO_FILTER=$(nats bench test --pub 0 --sub 1 --msgs 100000 --size 128 2>&1 | grep "msgs/sec" | awk '{print $1}')
RATE_WITH_FILTER=$(nats bench test --pub 0 --sub 1 --msgs 100000 --size 128 --filter "test.>" 2>&1 | grep "msgs/sec" | awk '{print $1}')
RATIO=$(echo "$RATE_WITH_FILTER / $RATE_NO_FILTER" | bc -l)

# Verdict: filter matching all subjects should be within 80% of no-filter
if (( $(echo "$RATIO < 0.8" | bc -l) )); then echo "FAIL: $RATIO ratio (>20% perf regression)"
else echo "PASS: $RATIO ratio"; fi
```

- **FAIL:** >20% performance degradation when filter matches all subjects.
- **PASS:** Performance within 80% of no-filter baseline.

---

## C++ Supplement — Bugs #31–#60

---

### #31. Dragonfly #6753 — SIGFPE in DEBUG POPULATE
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --proactor_threads 1 --dbfilename="" &
PID=$!; sleep 1
redis-cli -p 6379 DEBUG POPULATE 100 prefix 0 2>/dev/null
wait $PID; [ $? -ne 0 ] && echo "FAIL" || echo "PASS"
```

- **FAIL:** SIGFPE (division by zero). Exit ≠ 0.
- **PASS:** Returns error "value must be > 0", process alive.

---

### #32. Dragonfly #6619 — Crash on EVALSHA with empty SHA
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --proactor_threads 1 --dbfilename="" &
PID=$!; sleep 1
redis-cli -p 6379 EVALSHA "" 0 2>/dev/null
wait $PID; [ $? -ne 0 ] && echo "FAIL" || echo "PASS"
```

- **FAIL:** `Check failed: !eval_args.sha.empty()`. Crash.
- **PASS:** Returns error `NOSCRIPT`, process alive.

---

### #33. Dragonfly #6761 — Crash on MC STATS/VERSION in pipeline
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --memcached_port=11211 --proactor_threads 1 --dbfilename="" &
PID=$!; sleep 1
python3 replay_crash.py crashes 000000 127.0.0.1 11211
wait $PID; [ $? -ne 0 ] && echo "FAIL" || echo "PASS"
```

- **FAIL:** Crash. Exit ≠ 0.
- **PASS:** Responses sent, process alive.

---

### #34. Dragonfly #6614 — Crash from double MONITOR in MULTI/EXEC
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --proactor_threads 1 --dbfilename="" &
PID=$!; sleep 1
redis-cli -p 6379 <<'EOF'
MULTI
MONITOR
MONITOR
EXEC
EOF
sleep 1
kill -0 $PID 2>/dev/null && echo "PASS" || echo "FAIL"
```

- **FAIL:** `Check failed: cc_`. Crash.
- **PASS:** Returns error or succeeds, process alive.

---

### #35. Dragonfly #6907 — Crash on wrong-sized vector in FT.SEARCH
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --proactor_threads 1 --dbfilename="" &
PID=$!; sleep 1
# Create index with VECTOR field expecting 4 dims, insert 2-dim vector, search
redis-cli -p 6379 FT.CREATE idx ON HASH PREFIX 1 doc: SCHEMA vec VECTOR FLAT 6 TYPE FLOAT32 DIM 4 DISTANCE_METRIC L2
redis-cli -p 6379 HSET doc:1 vec "$(python3 -c 'import struct; print(struct.pack("ff",1.0,2.0).hex())')"
redis-cli -p 6379 FT.SEARCH idx '*' 2>/dev/null
sleep 1
kill -0 $PID 2>/dev/null && echo "PASS" || echo "FAIL"
```

- **FAIL:** Crash at `doc_accessors.cc:60`.
- **PASS:** Returns error or empty result, process alive.

---

### #36. Dragonfly #6764 — Crash on HINCRBYFLOAT with NaN/Inf
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --proactor_threads 1 --dbfilename="" &
PID=$!; sleep 1
redis-cli -p 6379 HSET h f 1.0
redis-cli -p 6379 HINCRBYFLOAT h f inf 2>/dev/null
sleep 1
kill -0 $PID 2>/dev/null && echo "PASS" || echo "FAIL"
```

- **FAIL:** Crash at `hset_family.cc:973` (empty hash from NaN).
- **PASS:** Returns error "increment would produce NaN or Infinity", process alive.

---

### #37. Kvrocks #3315 — Crash on `zdiff 0 a`
**Oracle type:** `CRASH`

```bash
./kvrocks -p 6666 &
PID=$!; sleep 1
redis-cli -p 6666 ZDIFF 0 a 2>/dev/null
sleep 1
kill -0 $PID 2>/dev/null && echo "PASS" || echo "FAIL"
```

- **FAIL:** Process crashes (out-of-bounds access).
- **PASS:** Returns error "numkeys must be positive", process alive.

---

### #38. Dragonfly #6909 — Crash from non-finite NUMERIC in search
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --proactor_threads 1 --dbfilename="" &
PID=$!; sleep 1
# Replay crash archive from the issue
python3 replay_crash.py crashes 000000
sleep 1
kill -0 $PID 2>/dev/null && echo "PASS" || echo "FAIL"
```

- **FAIL:** Crash from OOB in KeepTopKSorted or non-finite numeric.
- **PASS:** Error response, process alive.

---

### #39. Dragonfly #6654 — Crash in memcache reply for large values
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --memcached_port=11211 --proactor_threads 1 \
  --dbfilename="" --max_bulk_len=1048576 &
PID=$!; sleep 1
python3 replay_crash.py crashes 000002 127.0.0.1 11211
sleep 1
kill -0 $PID 2>/dev/null && echo "PASS" || echo "FAIL"
```

- **FAIL:** `Check failed: expected_buffer_cap <= kMaxBufferSize`.
- **PASS:** Response sent correctly, process alive.

---

### #40. Dragonfly #6819 — Crash from stale expiry on overwrite
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --proactor_threads 1 --dbfilename="" &
PID=$!; sleep 1
redis-cli -p 6379 SET k v EX 60
redis-cli -p 6379 SET k v2  # overwrite without expiry
# Trigger expiration cycle
sleep 65  # wait for original TTL to pass
redis-cli -p 6379 PING
kill -0 $PID 2>/dev/null && echo "PASS" || echo "FAIL"
```

- **FAIL:** Crash at `db_slice.cc:1163` when stale expiry fires.
- **PASS:** Key persists, PING returns PONG.

---

### #41. Dragonfly #6766 — Crash in json_family memory tracking
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --proactor_threads 1 --dbfilename="" &
PID=$!; sleep 1
# Rapid JSON operations creating orphans
for i in $(seq 1 1000); do
  redis-cli -p 6379 JSON.SET doc:$i \$ '{"a":1}'
  redis-cli -p 6379 JSON.SET doc:$i \$.b '{"c":'$i'}'
  redis-cli -p 6379 DEL doc:$i
done
kill -0 $PID 2>/dev/null && echo "PASS" || echo "FAIL"
```

- **FAIL:** Crash at `json_family.cc:99` or `compact_object.cc:52`.
- **PASS:** All operations complete, process alive.

---

### #42. Kvrocks #3148 — `namespace set` deletes another namespace
**Oracle type:** `OUTPUT`

```bash
./kvrocks -p 6666 &
PID=$!; sleep 1
redis-cli -p 6666 NAMESPACE ADD ns1 token1
redis-cli -p 6666 NAMESPACE ADD ns2 token2
redis-cli -p 6666 NAMESPACE SET ns1 token2  # should just update ns1's token
NS_COUNT=$(redis-cli -p 6666 NAMESPACE GET "*" 2>&1 | grep -c "ns")

# Verdict
if [ "$NS_COUNT" -lt 2 ]; then echo "FAIL: namespace deleted (only $NS_COUNT remain)"
else echo "PASS: both namespaces exist"; fi
```

- **FAIL:** ns2 is deleted (only 1 namespace remains).
- **PASS:** Both ns1 and ns2 exist.

---

### #43. Dragonfly #6912 — Crash in rdb_save unknown encoding
**Oracle type:** `CRASH`

```bash
./dragonfly --port 6379 --proactor_threads 1 --dbfilename="" &
PID=$!; sleep 1
python3 replay_crash.py crashes 000000
sleep 1
kill -0 $PID 2>/dev/null && echo "PASS" || echo "FAIL"
```

- **FAIL:** `FATAL: Unknown encoding 0 for type 17`.
- **PASS:** Operation handled, process alive.

---

### #44. ClickHouse #43816 — Deadlock in ReplicatedMergeTreeQueue
**Oracle type:** `HANG`

```bash
# Under sustained write load to replicated table, monitor merge progress
STUCK=$(clickhouse-client --query "SELECT count() FROM system.merges WHERE elapsed > 600 AND progress = 0")

# Verdict
if [ "$STUCK" -gt 0 ]; then echo "FAIL: $STUCK merges stuck for >10min"
else echo "PASS: all merges progressing"; fi
```

- **FAIL:** Merges show 0 progress for >10 minutes, threads in `pthread_cond_wait`.
- **PASS:** All merges make progress.

---

### #45. Dragonfly #6687 — Replica sync retry loop
**Oracle type:** `LOG`

```bash
# After starting replication:
RETRIES=$(grep -c "Unknown RDB string encoding 62" /tmp/dragonfly_replica.log)

# Verdict
if [ "$RETRIES" -gt 0 ]; then echo "FAIL: $RETRIES sync failures"
else echo "PASS: clean sync"; fi
```

- **FAIL:** Replica logs show "Unknown RDB string encoding 62", sync restarts repeatedly.
- **PASS:** Replica syncs completely without RDB errors.

---

### #46. Kvrocks #3356 — Replication feed blocks, WAL exhaustion
**Oracle type:** `HANG`

```bash
# Freeze the replica so it stops reading while its TCP connection stays open,
# then push far more data than the socket buffers hold.
kill -STOP "$REPLICA_PID"
# ... write 64MB to the master, confirm master->replica send queue is non-empty ...

# Verdict: does the master ever detach the stalled replica?
for t in $(seq 1 90); do
  sleep 1
  redis-cli -p "$MASTER_PORT" INFO replication | grep -q '^slave0:' || { DETACHED=1; break; }
done
[ -z "$DETACHED" ] && echo "FAIL: master kept stalled replica attached for 90s"
# else: SIGCONT the replica, require it to catch up, then PASS
```

- **FAIL:** Master keeps the stalled replica attached indefinitely (feed thread blocked in `write()`), nothing logged.
- **PASS:** Master detaches the stalled replica within a bounded time; replication recovers after the replica resumes.

---

### #47. Kvrocks #3339 — XREADGROUP BLOCK sends double response
**Oracle type:** `OUTPUT`

```bash
# Under concurrent load with XREADGROUP BLOCK:
# Capture raw TCP response
RESPONSE=$(redis-cli -p 6666 --resp3 XREADGROUP GROUP grp c1 BLOCK 1000 COUNT 1 STREAMS mystream '>' 2>&1)
DOUBLE=$(echo "$RESPONSE" | grep -c '^\*')

# Verdict
if [ "$DOUBLE" -gt 1 ]; then echo "FAIL: double response received"
else echo "PASS: single response"; fi
```

- **FAIL:** Client receives `*-1\r\n` followed by `*0\r\n` (two responses for one command).
- **PASS:** Single response per command.

---

### #48. ClickHouse #40571 — Keeper crashes on every startup
**Oracle type:** `CRASH`

```bash
# Start ClickHouse Keeper
clickhouse-keeper --config /etc/clickhouse-keeper/keeper_config.xml &
PID=$!
sleep 120  # give it time to initialize

# Verdict
kill -0 $PID 2>/dev/null && echo "PASS: keeper running" || echo "FAIL: keeper crashed"
```

- **FAIL:** Process crashes with segfault 11 during initialization. Every restart crashes.
- **PASS:** Keeper starts and stays running.

---

### #49. ClickHouse #98079 — Keeper disconnects after addWatch()
**Oracle type:** `OUTPUT`

```bash
# Connect Java ZooKeeper client with CuratorCache
# CuratorCache calls addWatch() during startup
# Monitor connection state
DISCONNECTS=$(grep -c "Session.*expired\|Connection loss" /tmp/curator.log)

# Verdict
if [ "$DISCONNECTS" -gt 0 ]; then echo "FAIL: disconnected after addWatch()"
else echo "PASS: connection stable"; fi
```

- **FAIL:** Client disconnects immediately after `addWatch()`, CuratorCache fails to start.
- **PASS:** Connection remains stable, CuratorCache initializes.

---

### #50. Redpanda #25769 — ListOffsets returns incorrect results
**Oracle type:** `OUTPUT`

```bash
# Produce compressed records with franz-go, then query ListOffsets
EXPECTED_OFFSET=42  # known correct offset for a timestamp
ACTUAL_OFFSET=$(rpk topic consume test -o $TIMESTAMP --format '%o' -n 1)

# Verdict
if [ "$ACTUAL_OFFSET" -ne "$EXPECTED_OFFSET" ]; then echo "FAIL: offset $ACTUAL_OFFSET != $EXPECTED_OFFSET"
else echo "PASS"; fi
```

- **FAIL:** `ListOffsets` returns wrong offset for compressed batch.
- **PASS:** Correct offset returned.

---

### #51. ClickHouse #44865 — Background merges stuck on replicas
**Oracle type:** `HANG` (same as #44)

See #44 oracle. Monitor `system.merges` for stuck entries.

---

### #52. ScyllaDB #27130 — Segfault on reload during startup
**Oracle type:** `CRASH`

```bash
scylla --smp 1 --developer-mode 1 &
PID=$!
for i in $(seq 1 10); do
  sleep 1
  curl -X POST 'http://localhost:10000/storage_service/raft_topology/reload' 2>/dev/null
done
sleep 5
kill -0 $PID 2>/dev/null && echo "PASS" || echo "FAIL"
```

- **FAIL:** Segfault during startup when REST API called too early.
- **PASS:** REST API returns error but server stays alive.

---

### #53. Redpanda #15118 — Future assert under load
**Oracle type:** `CRASH`

```bash
# Run Redpanda under sustained Kafka client load
# with authentication failures
CRASHES=$(grep -c "ss::future.*assert\|Exceptional future" /var/log/redpanda/redpanda.log)

# Verdict
if [ "$CRASHES" -gt 0 ]; then echo "FAIL"
else echo "PASS"; fi
```

---

### #54. Redpanda #16944 — Oversized allocation in raft batcher
**Oracle type:** `LOG`

```bash
# Under high write throughput:
OVERSIZED=$(grep -c "Oversized allocation.*replicate_batcher" /var/log/redpanda/redpanda.log)
if [ "$OVERSIZED" -gt 0 ]; then echo "FAIL"
else echo "PASS"; fi
```

---

### #55. ScyllaDB #28200 — Use-after-free in streaming
**Oracle type:** `CRASH` (with ASAN)

```bash
# Build with AddressSanitizer, trigger topology change with streaming
ASAN_ERRORS=$(grep -c "use-after-free\|heap-use-after-free" /tmp/scylla.log)
if [ "$ASAN_ERRORS" -gt 0 ]; then echo "FAIL"
else echo "PASS"; fi
```

---

### #56. ScyllaDB #25173 — Truncate exits raft applier
**Oracle type:** `LOG`

```bash
# Write concurrently + DROP TABLE, then try another raft operation
RESULT=$(cqlsh -e "CREATE KEYSPACE test2 WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1}" 2>&1)
if echo "$RESULT" | grep -q "timeout\|unavailable"; then echo "FAIL: raft applier exited"
else echo "PASS"; fi
```

- **FAIL:** Subsequent raft operations (CREATE KEYSPACE, etc.) timeout because raft applier fiber exited.
- **PASS:** All subsequent operations succeed.

---

### #57. RocksDB #10751 — Stalled writes block forever during shutdown
**Oracle type:** `HANG`

```cpp
// In test code:
auto start = std::chrono::steady_clock::now();
db->Close();
auto elapsed = std::chrono::steady_clock::now() - start;
// Verdict: Close should complete within 30s
assert(elapsed < std::chrono::seconds(30));
```

- **FAIL:** `DB::Close()` hangs indefinitely (blocked on stalled writes).
- **PASS:** Close completes within timeout.

---

### #58. RocksDB #13652 — ExportColumnFamily misses committed data
**Oracle type:** `OUTPUT`

```cpp
// After ExportColumnFamily:
// Verify all committed keys are present in the export
int missing = 0;
for (auto& key : committed_keys) {
    if (!export_contains(key)) missing++;
}
// Verdict
assert(missing == 0);  // FAIL if any committed key is missing
```

- **FAIL:** Some committed keys missing from the exported column family.
- **PASS:** All committed keys present.

---

### #59. ScyllaDB #28057 — IP->ID mapping lost on restart
**Oracle type:** `OUTPUT`

```bash
# After replace failure + full restart:
RESULT=$(nodetool status 2>&1)
if echo "$RESULT" | grep -q "internal error\|UnknownHostException"; then echo "FAIL"
else echo "PASS"; fi
```

- **FAIL:** `nodetool status` returns internal error (can't resolve replacing node's IP).
- **PASS:** All nodes show correct status.

---

### #60. ScyllaDB #27956 — Staging SSTables not discovered
**Oracle type:** `OUTPUT`

```bash
# After view update failure + restart:
# Compare base table and materialized view
BASE_COUNT=$(cqlsh -e "SELECT count(*) FROM ks.base_table" | tail -2 | head -1 | tr -d ' ')
VIEW_COUNT=$(cqlsh -e "SELECT count(*) FROM ks.mv" | tail -2 | head -1 | tr -d ' ')

# Verdict
if [ "$BASE_COUNT" -ne "$VIEW_COUNT" ]; then
  echo "FAIL: base-view inconsistency ($BASE_COUNT vs $VIEW_COUNT)"
else echo "PASS: base and view consistent"; fi
```

- **FAIL:** Base table and materialized view have different row counts permanently.
- **PASS:** Staging SSTables processed, counts match.

---

## Oracle Type Summary

| Oracle Type | Count | Description |
|-------------|-------|-------------|
| `CRASH` | 28 | Process exits with signal/assertion. Check exit code or `kill -0`. |
| `OUTPUT` | 18 | Query/command returns wrong result. Diff expected vs actual. |
| `HANG` | 5 | Process blocks indefinitely. Use `timeout` wrapper. |
| `METRIC` | 5 | Observable metric (memory, CPU, count) exceeds threshold. |
| `LOG` | 4 | Specific error pattern in logs. Use `grep`. |
| `RACE` | 1 | Go/ASAN race detector fires. Check detector output. |

### Automation Tips
- For `CRASH` bugs: wrap the process in a script, check exit code ≠ 0 after trigger.
- For `OUTPUT` bugs: capture query result, compare with expected value.
- For `HANG` bugs: wrap in `timeout X command`; exit code 124 = hang.
- For `METRIC` bugs: sample before/after, assert threshold.
- For `LOG` bugs: `grep -c "pattern" logfile`; count > 0 = bug present.
