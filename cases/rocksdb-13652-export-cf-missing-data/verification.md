# Verification: RocksDB #13652

## Test procedure
```bash
rm -rf /tmp/rocksdb_export_race /tmp/rocksdb_export_trial_*

/tmp/test_export_race
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "PASS: All exports included all committed data — bug is fixed"
else
  echo "FAIL: Some exports missed committed data — bug is present"
fi
```

## Simpler deterministic test
```bash
rm -rf /tmp/rocksdb_export_test /tmp/rocksdb_export_output /tmp/rocksdb_export_verify

/tmp/test_export_cf
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
  echo "PASS: Export included all 2000 committed keys"
else
  echo "FAIL: Export missed some committed keys"
fi
```

## Run multiple times for confidence (race condition)
```bash
FAILURES=0
for run in $(seq 1 10); do
  rm -rf /tmp/rocksdb_export_race /tmp/rocksdb_export_trial_*
  /tmp/test_export_race > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
  fi
done

if [ $FAILURES -gt 0 ]; then
  echo "FAIL: $FAILURES out of 10 runs had missing data — bug is present"
else
  echo "PASS: All 10 runs exported complete data — bug is fixed"
fi
```

- **FAIL:** `ExportColumnFamily` produces exports missing committed data (especially memtable data).
- **PASS:** All committed data is consistently included in the export, including memtable data.
