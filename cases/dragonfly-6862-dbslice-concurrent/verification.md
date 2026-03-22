# Verification: Dragonfly #6862

## Test procedure

1. Start Dragonfly in cluster mode:
   ```bash
   ./build-dbg/dragonfly \
     --port 6380 \
     --logtostderr \
     --proactor_threads 4 \
     --dbfilename="" \
     --cluster_mode=yes \
     --cluster_node_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa &
   PID=$!
   sleep 2
   ```

2. Configure cluster:
   ```bash
   redis-cli -p 6380 DFLYCLUSTER CONFIG '[{"slot_ranges":[{"start":0,"end":16383}],"master":{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ip":"127.0.0.1","port":6380},"replicas":[]}]'
   ```

3. Run concurrent stress test (writes + cluster ops):
   ```bash
   # Start write load
   redis-benchmark -p 6380 -t set -n 500000 -c 50 -d 100 -r 100000 &
   BENCH_PID=$!

   # Concurrent cluster operations
   CRASHED=false
   for i in $(seq 1 200); do
       if ! kill -0 $PID 2>/dev/null; then
           CRASHED=true
           break
       fi
       redis-cli -p 6380 DFLYCLUSTER FLUSHSLOTS $((i % 16384)) 2>/dev/null
       sleep 0.02
       redis-cli -p 6380 DFLYCLUSTER CONFIG '[{"slot_ranges":[{"start":0,"end":16383}],"master":{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ip":"127.0.0.1","port":6380},"replicas":[]}]' 2>/dev/null
       sleep 0.02
   done

   kill $BENCH_PID 2>/dev/null
   ```

4. Evaluate:
   ```bash
   if [ "$CRASHED" = "true" ]; then
       echo "FAIL: Bug is present — process crashed during concurrent operations"
   elif kill -0 $PID 2>/dev/null; then
       # Final health check
       PONG=$(redis-cli -p 6380 PING 2>/dev/null)
       if [ "$PONG" = "PONG" ]; then
           echo "PASS: Bug is fixed — process survived concurrent cluster ops + writes"
       else
           echo "INCONCLUSIVE: Process running but not responding"
       fi
   else
       echo "FAIL: Bug is present — process died"
   fi
   ```

5. Run the test 3 times for confidence (race condition):
   ```bash
   TOTAL_CRASHES=0
   for attempt in 1 2 3; do
       echo "=== Attempt $attempt ==="
       # Repeat steps 1-4, count crashes
   done

   if [ $TOTAL_CRASHES -gt 0 ]; then
       echo "FAIL: $TOTAL_CRASHES/3 runs crashed"
   else
       echo "PASS: 0/3 runs crashed"
   fi
   ```

6. Cleanup:
   ```bash
   kill $PID 2>/dev/null
   ```

## Verdict criteria
- **FAIL (bug present):** Dragonfly crashes (assert failure in `db_slice.cc:550` or segfault) during concurrent write + cluster management operations.
- **PASS (bug fixed):** Dragonfly survives all 3 rounds of concurrent stress testing without crashing.
- **Note:** Since this is a race condition, passing a single run is not conclusive. Run at least 3 iterations.
