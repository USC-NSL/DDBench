# Verification: etcd #20655

```bash
#!/bin/bash

rm -rf /tmp/etcd-watch-test
bin/etcd --data-dir /tmp/etcd-watch-test &
PID=$!
sleep 3

# Run the reproduction test from PR #20654 if available
# Otherwise use the manual repro approach
cd etcd
RESULT=$(go test -v -run TestWatchReliabilityHighFrequency ./tests/integration/ -count=1 -timeout 300s 2>&1)

kill $PID 2>/dev/null
rm -rf /tmp/etcd-watch-test

if echo "$RESULT" | grep -q "PASS"; then
    echo "PASS: Bug is fixed — no watch events dropped"
elif echo "$RESULT" | grep -q "FAIL"; then
    echo "FAIL: Bug is present — watch events dropped under high-frequency creation"
else
    echo "INCONCLUSIVE: Test did not produce clear PASS/FAIL — check output"
    echo "$RESULT" | tail -10
fi
```

- **FAIL:** Watch events are dropped; test reports missed events.
- **PASS:** All watch events delivered reliably.
