# Verification: ScyllaDB #28200

## Test procedure
Build with ASAN and run the topology change scenario from reproduce.md.

```bash
# After triggering a topology change (node join/decommission/rebuild):
sleep 60  # Wait for streaming to complete or crash

# Check if all nodes are still alive
ALL_ALIVE=true
for pid in $NODE1_PID $NODE2_PID; do
  if ! kill -0 $pid 2>/dev/null; then
    ALL_ALIVE=false
    echo "Node with PID $pid crashed"
  fi
done

# Check for ASAN errors in logs/stderr
if grep -rq "AddressSanitizer.*heap-use-after-free" /tmp/scylla-uaf-node*/system.log 2>/dev/null; then
  echo "FAIL: Use-after-free detected by ASAN — bug is present"
elif ! $ALL_ALIVE; then
  echo "FAIL: Node crashed (check logs for details) — bug is likely present"
else
  echo "PASS: Streaming completed without UAF — bug is fixed"
fi

# Also verify data integrity after topology change
ROWS=$(cqlsh 127.0.0.1 9042 -e "SELECT count(*) FROM test_ks.data;" 2>/dev/null | grep -oP '\d+')
echo "Row count after topology change: $ROWS"
```

- **FAIL:** ASAN reports a use-after-free in `streaming_task_impl::run`, or a node crashes during streaming.
- **PASS:** Topology change with streaming completes without ASAN errors and all nodes remain healthy.
