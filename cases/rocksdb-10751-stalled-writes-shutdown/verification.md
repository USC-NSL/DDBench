# Verification: RocksDB #10751

## Test procedure
```bash
rm -rf /tmp/rocksdb_stall_test

# Run the test program with a timeout
timeout 60 /tmp/test_stall_shutdown
EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  echo "FAIL: DB::Close() hung for 60+ seconds — bug is present"
elif [ $EXIT_CODE -eq 0 ]; then
  echo "PASS: DB::Close() completed normally — bug is fixed"
else
  echo "INCONCLUSIVE: Exit code $EXIT_CODE"
fi
```

## Multi-threaded test
```bash
rm -rf /tmp/rocksdb_stall_mt

timeout 60 /tmp/test_stall_mt
EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  echo "FAIL: DB::Close() hung — stalled writers blocked shutdown"
elif [ $EXIT_CODE -eq 0 ]; then
  echo "PASS: DB::Close() completed — stalled writers were woken up during shutdown"
else
  echo "INCONCLUSIVE: Exit code $EXIT_CODE"
fi
```

- **FAIL:** `DB::Close()` hangs indefinitely (timeout triggers); stalled writers are never woken up during shutdown.
- **PASS:** `DB::Close()` completes within a reasonable time; stalled writers are properly unblocked during the shutdown sequence.
