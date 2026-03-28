# Verification: Kvrocks #2214

## Test procedure

```bash
#!/bin/bash

# Start master with repl-namespace-enabled
./build/kvrocks -c master.conf &
MASTER_PID=$!
sleep 2

# Start slave
./build/kvrocks -c slave.conf &
SLAVE_PID=$!
sleep 5

# Set initial key
redis-cli -p 12214 SET test1 value1
sleep 2

# Verify initial replication
INITIAL=$(redis-cli -p 12215 GET test1 2>/dev/null)
if [ "$INITIAL" != "value1" ]; then
    echo "ERROR: Initial replication failed"
    kill $MASTER_PID $SLAVE_PID 2>/dev/null
    exit 1
fi

# Stop slave
kill $SLAVE_PID 2>/dev/null
wait $SLAVE_PID 2>/dev/null
sleep 1

# Write updates on master while slave is down
redis-cli -p 12214 SET test1 value2
redis-cli -p 12214 SET test2 newvalue

# Restart slave
./build/kvrocks -c slave.conf &
SLAVE_PID=$!
sleep 5

# Check replicated values
VAL1=$(redis-cli -p 12215 GET test1 2>/dev/null)
VAL2=$(redis-cli -p 12215 GET test2 2>/dev/null)

kill $MASTER_PID $SLAVE_PID 2>/dev/null
wait $MASTER_PID $SLAVE_PID 2>/dev/null

if [ "$VAL1" = "value2" ] && [ "$VAL2" = "newvalue" ]; then
    echo "PASS: Bug is fixed — slave correctly received all key updates after restart"
else
    echo "FAIL: Bug is present — slave lost key updates (test1='$VAL1', test2='$VAL2')"
fi
```

## Pass/fail criteria

- **FAIL (bug present):** After the slave restarts and reconnects, keys updated on the master during slave downtime have stale values on the slave. The replication appears healthy but data is silently inconsistent.
- **PASS (bug fixed):** After the slave restarts and reconnects, all keys updated on the master during downtime are correctly replicated. `test1` is `"value2"` and `test2` is `"newvalue"` on the slave.
