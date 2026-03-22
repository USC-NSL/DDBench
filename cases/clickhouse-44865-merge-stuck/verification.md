# Verification: ClickHouse #44865

## Test procedure

1. Set up the replicated cluster (see setup.md) and create the replicated table.

2. Start sustained write load (see reproduce.md).

3. Monitor both replicas for 30-60 minutes:
   ```bash
   while true; do
       PARTS=$(clickhouse-client --port 9000 -q "SELECT count() FROM system.parts WHERE active AND table = 'test_merges'")
       MERGES=$(clickhouse-client --port 9000 -q "SELECT count() FROM system.merges WHERE table = 'test_merges'")
       echo "$(date): replica1 — parts=$PARTS merges=$MERGES"

       PARTS2=$(clickhouse-client --port 9001 -q "SELECT count() FROM system.parts WHERE active AND table = 'test_merges'")
       MERGES2=$(clickhouse-client --port 9001 -q "SELECT count() FROM system.merges WHERE table = 'test_merges'")
       echo "$(date): replica2 — parts=$PARTS2 merges=$MERGES2"

       sleep 30
   done
   ```

4. Evaluate:
   ```bash
   # Check if either replica has stuck merges (many parts, 0 merges for extended period)
   PARTS=$(clickhouse-client --port 9000 -q "SELECT count() FROM system.parts WHERE active AND table = 'test_merges'")
   MERGES=$(clickhouse-client --port 9000 -q "SELECT count() FROM system.merges WHERE table = 'test_merges'")

   if [ "$PARTS" -gt 200 ] && [ "$MERGES" -eq 0 ]; then
       echo "FAIL: Bug is present — merges stuck on replica (parts=$PARTS, merges=$MERGES)"
   elif [ "$PARTS" -lt 100 ]; then
       echo "PASS: Bug is fixed — merges keeping up (parts=$PARTS, merges=$MERGES)"
   else
       echo "INCONCLUSIVE: parts=$PARTS merges=$MERGES — continue monitoring"
   fi
   ```

5. Cleanup:
   ```bash
   clickhouse-client -q "DROP TABLE IF EXISTS test_merges ON CLUSTER test_cluster"
   docker-compose down
   ```

## Verdict criteria
- **FAIL (bug present):** One or both replicas show 0 active merges while parts count exceeds 200 and continues growing, eventually causing insert failures with "Too many parts."
- **PASS (bug fixed):** Both replicas maintain active merges and keep parts count stable (under ~100) throughout sustained write load.
- **Note:** This bug is timing-dependent and may require extended testing (30-60+ minutes under load) to confirm.
