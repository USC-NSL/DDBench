# Verification: Kvrocks #2520

## Test procedure

```bash
#!/bin/bash
# Start master with namespaces
mkdir -p /tmp/kvrocks-master/logs /tmp/kvrocks-slave/logs

cat > /tmp/kvrocks-master.conf <<'EOF'
bind 0.0.0.0
port 12520
dir /tmp/kvrocks-master
log-dir /tmp/kvrocks-master/logs
requirepass foobared
masterauth foobared
EOF

cat > /tmp/kvrocks-slave.conf <<'EOF'
bind 0.0.0.0
port 12521
dir /tmp/kvrocks-slave
log-dir /tmp/kvrocks-slave/logs
requirepass foobared
masterauth foobared
EOF

./build/kvrocks -c /tmp/kvrocks-master.conf &
MASTER_PID=$!
sleep 2

# Add namespaces on master
redis-cli -p 12520 -a foobared NAMESPACE ADD ns1 token1
redis-cli -p 12520 -a foobared NAMESPACE ADD ns2 token2

# Start slave and trigger full sync
./build/kvrocks -c /tmp/kvrocks-slave.conf &
SLAVE_PID=$!
sleep 2
redis-cli -p 12521 -a foobared SLAVEOF 127.0.0.1 12520

# Wait for sync
sleep 15

# Check namespaces on slave
RESULT=$(redis-cli -p 12521 -a foobared NAMESPACE GET '*' 2>/dev/null)

# Cleanup
kill $MASTER_PID $SLAVE_PID 2>/dev/null
wait $MASTER_PID $SLAVE_PID 2>/dev/null
rm -rf /tmp/kvrocks-master /tmp/kvrocks-slave
rm -f /tmp/kvrocks-master.conf /tmp/kvrocks-slave.conf

# Check if both ns1 and ns2 are visible
if echo "$RESULT" | grep -q "ns1" && echo "$RESULT" | grep -q "ns2"; then
    echo "PASS: Bug is fixed — all namespaces visible on slave after full sync"
else
    echo "FAIL: Bug is present — namespaces missing on slave after full sync"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** Only the default namespace is visible on the slave after full sync. `ns1` and `ns2` are missing from `NAMESPACE GET *` output. A server restart would make them appear.
- **PASS (bug fixed):** All namespaces (`ns1`, `ns2`, and default) are visible on the slave immediately after full sync completes, without requiring a restart.
