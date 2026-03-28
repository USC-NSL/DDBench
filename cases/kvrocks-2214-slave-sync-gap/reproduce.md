# Reproduce: Kvrocks #2214

## Prerequisites
A Kvrocks master-slave setup with `repl-namespace-enabled yes` (see setup.md).

## Step 1: Start master and slave

```bash
./build/kvrocks -c master.conf &
./build/kvrocks -c slave.conf &
```

Wait for replication to establish:
```bash
redis-cli -p 12215 INFO replication
# Should show master_link_status:up
```

## Step 2: Write initial data and verify replication

```bash
redis-cli -p 12214 SET test1 value1
redis-cli -p 12215 GET test1
# Should return "value1"
```

## Step 3: Stop the slave

```bash
# Kill the slave process
kill <slave_pid>
```

## Step 4: Write updates on master while slave is down

```bash
redis-cli -p 12214 SET test1 value2
redis-cli -p 12214 SET test2 newvalue
```

## Step 5: Restart the slave

```bash
./build/kvrocks -c slave.conf &
```

Wait for replication to re-establish:
```bash
redis-cli -p 12215 INFO replication
# Wait until master_link_status:up
```

## Step 6: Check slave for replicated keys

```bash
redis-cli -p 12215 GET test1
# Expected: "value2"

redis-cli -p 12215 GET test2
# Expected: "newvalue"
```

## Expected result (bug present)
- `test1` returns the old value `"value1"` instead of `"value2"` on the slave.
- `test2` may or may not be present depending on how many operations were skipped.
- No errors in logs; replication status shows healthy.

## Expected result (fixed)
- `test1` returns `"value2"` on the slave.
- `test2` returns `"newvalue"` on the slave.
- All updates from master during slave downtime are correctly replicated.
