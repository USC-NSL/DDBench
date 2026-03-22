# Reproduce: Dragonfly #6614

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Trigger the bug
```bash
redis-cli -p 6379 MULTI
redis-cli -p 6379 MONITOR
redis-cli -p 6379 MONITOR
redis-cli -p 6379 EXEC
```
Or in a single redis-cli session:
```
MULTI
MONITOR
MONITOR
EXEC
```

## Expected result (bug present)
The Dragonfly process crashes.
