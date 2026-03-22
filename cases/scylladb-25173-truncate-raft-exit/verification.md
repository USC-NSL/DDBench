# Verification: ScyllaDB #25173

## Test procedure
Run the reproduction steps from reproduce.md, then test if raft operations still work.

```bash
# After dropping the table with concurrent writes, try a schema change:
RESULT=$(timeout 30 cqlsh 127.0.0.1 9042 -e "CREATE TABLE test_ks.verify_table (id int PRIMARY KEY);" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "PASS: Schema operation succeeded — raft applier is alive — bug is fixed"
  # Clean up
  cqlsh 127.0.0.1 9042 -e "DROP TABLE test_ks.verify_table;" 2>/dev/null
elif [ $EXIT_CODE -eq 124 ]; then
  echo "FAIL: Schema operation timed out — raft applier fiber is dead — bug is present"
else
  echo "INCONCLUSIVE: Schema operation failed with error: $RESULT"
fi
```

Also check logs for the raft applier exit:
```bash
grep -i "raft.*applier.*fiber.*exit\|raft.*applier.*error" /tmp/scylla-truncate/system.log 2>/dev/null
if [ $? -eq 0 ]; then
  echo "FAIL: Raft applier fiber exit detected in logs"
else
  echo "PASS: No raft applier fiber exit in logs"
fi
```

- **FAIL:** Schema operations hang after DROP TABLE with concurrent writes; logs show raft applier fiber exited.
- **PASS:** Schema operations succeed normally after DROP TABLE with concurrent writes; raft applier remains active.
