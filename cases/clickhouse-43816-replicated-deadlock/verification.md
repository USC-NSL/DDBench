# Verification: ClickHouse #43816

## Test procedure

After starting sustained writes (see reproduce.md), monitor merge progress for 15 minutes:

```bash
#!/bin/bash
STUCK_COUNT=0
for i in $(seq 1 30); do
    sleep 30
    MERGES=$(clickhouse-client --port 9001 -q "
        SELECT count() FROM system.merges WHERE progress = 0 AND elapsed > 600")
    if [ "$MERGES" -gt "0" ]; then
        STUCK_COUNT=$((STUCK_COUNT + 1))
    fi
done

if [ "$STUCK_COUNT" -gt "3" ]; then
    echo "FAIL: Bug is present — merges stuck with 0 progress for >10 min"
else
    echo "PASS: Bug is fixed — merges progressing normally"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** `system.merges` shows entries with `progress = 0` and `elapsed > 600` (10 minutes). Thread dumps show threads stuck in `setActualPartName` / `pthread_cond_wait`. The number of active parts in `system.parts` grows without bound.
- **PASS (bug fixed):** Merges complete normally under sustained write load. No merges remain stuck at 0 progress for more than a few minutes. Part count stabilizes.

Additional check:
```sql
-- Part count should stabilize, not grow unbounded
SELECT count() FROM system.parts
WHERE table = 'test_replicated' AND active = 1;
```
