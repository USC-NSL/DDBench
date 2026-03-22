# Reproduce: Dragonfly #6619

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Trigger the bug
```bash
redis-cli -p 6379 EVALSHA "" 0
```

## Expected result (bug present)
The Dragonfly process crashes.
