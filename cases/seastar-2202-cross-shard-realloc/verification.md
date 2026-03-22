# Verification: Seastar #2202

## Test

Run the cross-shard realloc test (see reproduce.md):

```bash
./test_cross_shard_realloc --smp 2
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq "0" ]; then
    echo "PASS: Bug is fixed — cross-shard realloc shrink succeeded"
else
    echo "FAIL: Bug is present — process crashed (exit code $EXIT_CODE)"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** The process crashes with assertion failure `object_cpu_id(ptr) == cpu_id`. Exit code is non-zero (typically 134 for SIGABRT).
- **PASS (bug fixed):** The cross-shard realloc to a smaller size completes without crash. The process exits normally with code 0.
