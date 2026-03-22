# Verification: etcd #20704

```bash
#!/bin/bash

rm -rf /tmp/etcd-leasing-test
bin/etcd --data-dir /tmp/etcd-leasing-test &
PID=$!
sleep 3

cd etcd

# Run leasing tests with race detector
RESULT=$(go test -race -v -run TestLeasingLinearizability ./client/v3/leasing/ -count=1 -timeout 120s 2>&1)

kill $PID 2>/dev/null
rm -rf /tmp/etcd-leasing-test

if echo "$RESULT" | grep -q "PASS"; then
    echo "PASS: Bug is fixed — leasing cache is linearizable"
elif echo "$RESULT" | grep -q "FAIL"; then
    echo "FAIL: Bug is present — leasing cache violates linearizability"
else
    # Fallback: run the manual repro
    echo "INCONCLUSIVE: No specific test found. Run manual reproduction."
    echo "$RESULT" | tail -10
fi
```

Manual verification approach:

```bash
#!/bin/bash
# After running the reproduce steps, check output:
# If "BUG" appears in the output → FAIL
# If "No bug detected" → PASS (but may be non-deterministic; run multiple times)

for run in $(seq 1 5); do
  echo "=== Run $run ==="
  OUTPUT=$(cd /tmp && go run leasing_bug_test.go 2>&1)
  echo "$OUTPUT"
  if echo "$OUTPUT" | grep -q "BUG"; then
    echo "FAIL: Bug is present — leasing cache returned stale/incorrect data"
    exit 1
  fi
done
echo "PASS: Bug is fixed (or not triggered in 5 runs)"
```

- **FAIL:** Cache returns data inconsistent with actual etcd state under concurrent operations.
- **PASS:** Cache state always matches etcd state.
