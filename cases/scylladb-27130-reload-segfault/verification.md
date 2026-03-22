# Verification: ScyllaDB #27130

## Test procedure

1. Start the trigger script that calls the REST API continuously:
   ```bash
   (while true; do
       curl -s -X POST http://localhost:10000/storage_service/raft_topology/reload 2>/dev/null
       sleep 0.1
   done) &
   TRIGGER_PID=$!
   ```

2. Start ScyllaDB:
   ```bash
   docker rm -f scylla 2>/dev/null
   docker run -d --name scylla --network host \
     scylladb/scylla:6.2.2 \
     --smp 2 \
     --memory 1G \
     --overprovisioned
   ```

3. Wait for startup to either complete or crash:
   ```bash
   sleep 60
   ```

4. Check if the node is running:
   ```bash
   RUNNING=$(docker inspect scylla --format='{{.State.Running}}' 2>/dev/null)
   EXIT_CODE=$(docker inspect scylla --format='{{.State.ExitCode}}' 2>/dev/null)
   ```

5. Evaluate:
   ```bash
   kill $TRIGGER_PID 2>/dev/null

   if [ "$RUNNING" = "true" ]; then
       # Try the reload endpoint now that startup is complete
       RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
           http://localhost:10000/storage_service/raft_topology/reload)
       if [ "$RESPONSE" = "200" ] || [ "$RESPONSE" = "503" ]; then
           echo "PASS: Bug is fixed — node survived API calls during startup"
       else
           echo "PASS: Bug is fixed — node is running (API response: $RESPONSE)"
       fi
   else
       echo "FAIL: Bug is present — node crashed during startup (exit code: $EXIT_CODE)"
   fi
   ```

6. Run the test 3 times to increase confidence (the timing window may be narrow):
   ```bash
   for attempt in 1 2 3; do
       echo "Attempt $attempt..."
       # Repeat steps 1-5
   done
   ```

7. Cleanup:
   ```bash
   docker rm -f scylla 2>/dev/null
   ```

## Verdict criteria
- **FAIL (bug present):** ScyllaDB crashes with exit code 139 (SIGSEGV) during startup while the REST API is being called.
- **PASS (bug fixed):** ScyllaDB completes startup successfully despite concurrent REST API calls. The API either returns an error during initialization or handles the request gracefully.
