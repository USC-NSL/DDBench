# Reproduce: Dragonfly #6753

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Send the crashing command
```bash
redis-cli -p 6379 DEBUG POPULATE 100 prefix 0
```

## Expected result (bug present)
The process crashes with SIGFPE. The third argument `0` is the `val_size` parameter.
