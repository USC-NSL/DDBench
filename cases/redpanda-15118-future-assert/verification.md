# Verification: Redpanda #15118

## Test procedure
Run the reproduction steps from reproduce.md. After the sustained authentication failure load:

```bash
# Check if Redpanda is still running
if kill -0 $RPANDA_PID 2>/dev/null; then
  # Verify it's responsive
  HEALTH=$(curl -s http://localhost:9644/v1/cluster/health_overview)
  if echo "$HEALTH" | grep -q "is_healthy"; then
    echo "PASS: Redpanda survived auth failure load — bug is fixed"
  else
    echo "INCONCLUSIVE: Process alive but not responding to health check"
  fi
else
  echo "FAIL: Redpanda crashed — bug is present"
fi
```

Also check the Redpanda logs for exceptional future warnings:
```bash
grep -i "exceptional future\|broken.promise\|FATAL" /tmp/redpanda-data/redpanda.log 2>/dev/null
if [ $? -eq 0 ]; then
  echo "FAIL: Exceptional future or broken promise found in logs"
else
  echo "PASS: No exceptional future errors in logs"
fi
```

- **FAIL:** Redpanda process crashes or logs contain "Exceptional future ignored" / "broken_promise" errors during authentication failures.
- **PASS:** Redpanda remains healthy and responsive through sustained authentication failure load, with no exceptional future warnings in logs.
