# Verification: etcd #20269

## Test procedure
Run the full reproduction steps from reproduce.md. After re-adding and restarting node3:

```bash
sleep 10

# Check if node3 is still alive
if kill -0 $NODE3_PID 2>/dev/null; then
  # Also verify it joined the cluster
  HEALTH=$(bin/etcdctl --endpoints=http://127.0.0.1:2383 endpoint health 2>&1)
  if echo "$HEALTH" | grep -q "is healthy"; then
    echo "PASS: Node3 rejoined successfully — bug is fixed"
  else
    echo "INCONCLUSIVE: Node3 is alive but not healthy — check logs"
  fi
else
  echo "FAIL: Node3 crashed — bug is present"
fi
```

Also check node3's logs for the panic:
```bash
# If using file logging, check for the panic string
grep -q "tocommit.*is out of range" /tmp/etcd-rejoin-node3.log 2>/dev/null && echo "FAIL: Panic found in logs"
```

- **FAIL:** Node3 panics with "tocommit(X) is out of range [lastIndex(0)]" and exits.
- **PASS:** Node3 starts cleanly, catches up with the cluster, and responds to health checks.
