# Verification: ScyllaDB #28057

## Test procedure
Run the full reproduction sequence from reproduce.md. After restarting nodes 1 and 2:

```bash
sleep 30  # Allow cluster to stabilize

# Check nodetool status
STATUS=$(nodetool -h 127.0.0.1 status 2>&1)
echo "$STATUS"

if echo "$STATUS" | grep -qi "error\|exception\|unknown\|failed"; then
  echo "FAIL: nodetool status shows errors — IP/ID mapping issue — bug is present"
else
  echo "Checking further..."
fi

# Verify cluster can perform operations
QUERY_RESULT=$(cqlsh 127.0.0.1 9042 -e "SELECT count(*) FROM test_ks.data;" 2>&1)
if echo "$QUERY_RESULT" | grep -q "^[[:space:]]*[0-9]"; then
  echo "Query succeeded"
else
  echo "FAIL: Query failed after restart — cluster unhealthy"
fi

# Try a schema change to verify raft topology is functional
SCHEMA_RESULT=$(timeout 30 cqlsh 127.0.0.1 9042 -e "CREATE TABLE test_ks.verify (id int PRIMARY KEY);" 2>&1)
if [ $? -eq 0 ]; then
  echo "PASS: Schema change succeeded — raft topology functional — bug is fixed"
  cqlsh 127.0.0.1 9042 -e "DROP TABLE test_ks.verify;" 2>/dev/null
else
  echo "FAIL: Schema change failed or timed out — raft topology broken — bug is present"
fi
```

- **FAIL:** `nodetool status` shows errors, or topology/schema operations fail after restarting nodes following a failed replace.
- **PASS:** `nodetool status` shows correct cluster state, and schema/topology operations work normally after restart.
