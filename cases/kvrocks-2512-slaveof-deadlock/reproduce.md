# Reproduce: Kvrocks #2512

## Prerequisites
- Kvrocks built from the buggy commit
- `redis-cli` available (for interacting with Kvrocks)

## Reproduction Strategy
The deadlock race window is extremely narrow (microseconds) and requires the
replication thread to be inside `PrepareRestoreDB()` waiting for
`WorkExclusivityGuard` when a second `SLAVEOF` command arrives. To reproduce
deterministically, the script:
1. Instruments the source with a 2-second sleep in `PrepareRestoreDB` before
   the lock acquisition, widening the race window
2. Enables `use-rsid-psync yes` so switching between masters forces a full sync
   (PSYNC fails due to different replication IDs), which is the code path that
   calls `PrepareRestoreDB`

## Step 1: Start two master instances
```bash
./build/kvrocks -c master1.conf &
# master1.conf: bind 0.0.0.0, port 12512, use-rsid-psync yes

./build/kvrocks -c master2.conf &
# master2.conf: bind 0.0.0.0, port 12513, use-rsid-psync yes
```

## Step 2: Start the slave instance
```bash
./build/kvrocks -c slave.conf &
# slave.conf: bind 0.0.0.0, port 12514, use-rsid-psync yes,
#             slave-empty-db-before-fullsync yes
```

## Step 3: Write data and establish replication with master2
```bash
redis-cli -p 12512 SET m1key m1val
redis-cli -p 12513 SET m2key m2val
redis-cli -p 12514 SLAVEOF 127.0.0.1 12513
# Wait for sync to complete (~5s)
```

## Step 4: Switch to master1 (triggers full sync)
```bash
redis-cli -p 12514 SLAVEOF 127.0.0.1 12512
# Repl thread fails PSYNC (different repl ID), enters full sync.
# PrepareRestoreDB is called, hits the instrumented 2s sleep.
```

## Step 5: Send second SLAVEOF during the sleep window
```bash
sleep 0.5  # Wait for repl thread to enter PrepareRestoreDB
redis-cli -p 12514 SLAVEOF 127.0.0.1 12513
# This command hangs because the worker thread deadlocks
```

## Expected result (bug present)
The second `SLAVEOF` command hangs indefinitely. The slave becomes completely
unresponsive. The worker thread holding `WorkExclusivityGuard` is blocked on
`thread.join()` waiting for the replication thread, which is blocked waiting
for the same exclusive lock.
