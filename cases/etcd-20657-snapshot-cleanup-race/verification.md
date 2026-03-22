# Verification: etcd #20657

## Automated test
```bash
rm -rf /tmp/etcd-node{1,2,3}

# Start 3-node cluster with --snapshot-count=2
# (See setup.md for full node start commands)
# Save PIDs
PIDS=()
# ... start each node, capture PID ...

sleep 3

# Generate rapid writes + leader changes concurrently
for i in $(seq 1 5000); do
  bin/etcdctl --endpoints=http://127.0.0.1:2379 put key-$i value-$i 2>/dev/null &
done

for i in $(seq 1 10); do
  bin/etcdctl --endpoints=http://127.0.0.1:2379 move-leader $(bin/etcdctl --endpoints=http://127.0.0.1:2379 endpoint status --write-out=json 2>/dev/null | python3 -c "import sys,json; eps=json.load(sys.stdin); print(eps[0]['Status']['leader'])" 2>/dev/null) 2>/dev/null || true
  sleep 0.5
done

wait
sleep 5

# Check all nodes are still alive
PASS=true
for port in 2379 2381 2383; do
  if ! bin/etcdctl --endpoints=http://127.0.0.1:$port endpoint health 2>/dev/null; then
    PASS=false
    echo "Node on port $port is DOWN"
  fi
done

if $PASS; then
  echo "PASS: All nodes survived — bug is fixed"
else
  echo "FAIL: At least one node crashed — bug is present"
fi

# Cleanup
for pid in "${PIDS[@]}"; do kill $pid 2>/dev/null; done
```

- **FAIL:** One or more nodes crash with "file not found" panic on a `.snap.db` file.
- **PASS:** All three nodes remain healthy after rapid writes and leader changes with `--snapshot-count=2`.
