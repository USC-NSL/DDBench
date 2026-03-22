# Verification: ScyllaDB #27956

## Test procedure
Run the full reproduction from reproduce.md. After restarting the node and waiting for initialization:

```bash
sleep 30  # Allow view update generator to process any staging SSTables

BASE_COUNT=$(cqlsh 127.0.0.1 9042 -e "SELECT count(*) FROM test_ks.base_table;" 2>/dev/null | grep -oP '\d+' | head -1)
VIEW_COUNT=$(cqlsh 127.0.0.1 9042 -e "SELECT count(*) FROM test_ks.by_category;" 2>/dev/null | grep -oP '\d+' | head -1)

echo "Base table rows: $BASE_COUNT"
echo "View rows: $VIEW_COUNT"

if [ -z "$BASE_COUNT" ] || [ -z "$VIEW_COUNT" ]; then
  echo "INCONCLUSIVE: Could not query tables"
elif [ "$BASE_COUNT" -eq "$VIEW_COUNT" ]; then
  echo "PASS: Base and view are consistent ($BASE_COUNT rows each) — bug is fixed"
else
  DIFF=$(( BASE_COUNT - VIEW_COUNT ))
  echo "FAIL: View is missing $DIFF rows — staging SSTables not processed — bug is present"
fi
```

Also check for staging SSTables on disk:
```bash
# Look for staging SSTables in the data directory
STAGING_FILES=$(find /tmp/scylla-staging/data -path "*/staging/*" -name "*.db" 2>/dev/null | wc -l)
if [ "$STAGING_FILES" -gt 0 ]; then
  echo "WARNING: $STAGING_FILES staging SSTable files found — view updates still pending"
else
  echo "No staging SSTables — all processed"
fi
```

- **FAIL:** Materialized view has fewer rows than base table after restart; staging SSTables remain unprocessed.
- **PASS:** Base table and materialized view have the same row count after restart; staging SSTables are processed by the view update generator.
