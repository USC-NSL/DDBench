# Verification: ClickHouse #40571

## Test procedure

1. Start Keeper (see reproduce.md for full config):
   ```bash
   docker rm -f keeper 2>/dev/null
   docker run -d --name keeper --network host \
     -v $(pwd)/keeper_config.xml:/etc/clickhouse-keeper/keeper_config.xml \
     clickhouse/clickhouse-keeper:22.7
   ```

2. Wait for startup:
   ```bash
   sleep 10
   ```

3. Check if the process is still running:
   ```bash
   RUNNING=$(docker inspect keeper --format='{{.State.Running}}' 2>/dev/null)
   ```

4. Try connecting:
   ```bash
   RESPONSE=$(echo ruok | nc -w 3 localhost 2181 2>/dev/null)
   ```

5. Evaluate:
   ```bash
   if [ "$RUNNING" = "true" ] && [ "$RESPONSE" = "imok" ]; then
       echo "PASS: Bug is fixed — Keeper started successfully"
   else
       EXIT_CODE=$(docker inspect keeper --format='{{.State.ExitCode}}' 2>/dev/null)
       echo "FAIL: Bug is present — Keeper crashed (exit code: $EXIT_CODE)"
       docker logs keeper 2>&1 | tail -10
   fi
   ```

6. Cleanup:
   ```bash
   docker rm -f keeper 2>/dev/null
   ```

## Verdict criteria
- **FAIL (bug present):** The Keeper container exits with a non-zero exit code (139 for SIGSEGV) and does not respond to `ruok`.
- **PASS (bug fixed):** The Keeper container stays running and responds with `imok` to the `ruok` command on port 2181.
