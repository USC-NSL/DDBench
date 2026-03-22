# Verification: Redpanda #16944

## Test procedure
Run the high-throughput write workload from reproduce.md and check logs.

```bash
# After running the high-throughput workload for at least 60 seconds:

# Check for oversized allocation warnings
OVERSIZED=$(grep -c "oversized allocation.*replicate_batcher" /tmp/redpanda-data/redpanda.log 2>/dev/null || echo "0")

if [ "$OVERSIZED" -gt 0 ]; then
  echo "FAIL: Found $OVERSIZED oversized allocation warnings from replicate_batcher — bug is present"
else
  echo "PASS: No oversized allocation warnings from replicate_batcher — bug is fixed"
fi
```

Alternative check via admin API metrics:
```bash
# Check Seastar allocator metrics for large allocations
curl -s http://localhost:9644/metrics | grep -i "oversized\|large_alloc" || true
```

- **FAIL:** Log contains "oversized allocation" warnings referencing `raft::replicate_batcher::flush` during high-throughput writes.
- **PASS:** No oversized allocation warnings from the replicate batcher under the same workload.
