# Verification: etcd #20793

## Test procedure
Run the full multi-version upgrade sequence from reproduce.md.

After attempting the final upgrade to 3.6.x:
```bash
sleep 10

# Check if all nodes started successfully on 3.6.x
PASS=true
for port in 2379 2381 2383; do
  if ! /tmp/etcd-v3.6.4-linux-amd64/etcdctl --endpoints=http://127.0.0.1:$port endpoint health 2>/dev/null; then
    PASS=false
    echo "Node on port $port is not healthy"
  fi
done

# Also verify member list shows correct roles (no spurious learners)
MEMBER_LIST=$(/tmp/etcd-v3.6.4-linux-amd64/etcdctl --endpoints=http://127.0.0.1:2379 member list 2>&1)
if echo "$MEMBER_LIST" | grep -qi "learner"; then
  echo "FAIL: Cluster still shows learner members after promotion"
  PASS=false
fi

if $PASS; then
  echo "PASS: Cluster upgraded successfully — bug is fixed"
else
  echo "FAIL: Upgrade failed — bug is present"
fi
```

- **FAIL:** The final upgrade to 3.6.x fails with "too many learner members in cluster" or the member list incorrectly shows promoted members as learners.
- **PASS:** All nodes successfully upgrade to 3.6.x and the member list correctly reflects all promoted members as voters.
