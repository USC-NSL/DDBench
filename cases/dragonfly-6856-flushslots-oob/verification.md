# Verification: Dragonfly #6856

## Test procedure
1. Start Dragonfly in cluster mode:
   ```bash
   ./build-dbg/dragonfly \
     --port 6380 \
     --logtostderr \
     --proactor_threads 1 \
     --dbfilename="" \
     --cluster_mode=yes \
     --cluster_node_id=0000000000000000000000000000000000000000 &
   PID=$!
   sleep 2
   ```

2. Send the invalid command:
   ```bash
   redis-cli -p 6380 DFLYCLUSTER FLUSHSLOTS 16384 2>/dev/null
   ```

3. Check if the process is still alive:
   ```bash
   sleep 1
   if kill -0 $PID 2>/dev/null; then
       echo "PASS: Bug is fixed — process survived invalid slot ID"
   else
       wait $PID
       echo "FAIL: Bug is present — process crashed (exit code: $?)"
   fi
   ```

4. Cleanup:
   ```bash
   kill $PID 2>/dev/null
   ```

## Verdict criteria
- **FAIL (bug present):** The Dragonfly process crashes (exit code != 0) when
  receiving `DFLYCLUSTER FLUSHSLOTS 16384`.
- **PASS (bug fixed):** The Dragonfly process returns an error response to the
  client (e.g., "ERR invalid slot id") but remains running. A subsequent
  `redis-cli -p 6380 PING` returns `PONG`.
