# Reproduce: Dragonfly #6764

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Trigger the bug
```bash
redis-cli -p 6379 HSET myhash field 1.0
redis-cli -p 6379 HINCRBYFLOAT myhash field inf
```

## Expected result (bug present)
The Dragonfly process crashes.
