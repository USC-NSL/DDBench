# Reproduce: Dragonfly #6819

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Set a key with expiry, then overwrite without expiry
```bash
# Set key with 5-second expiry
redis-cli -p 6379 SET mykey "value1" EX 5

# Immediately overwrite without expiry
redis-cli -p 6379 SET mykey "value2"
```

## Step 3: Wait for the original expiry to fire
```bash
# Wait for the expiry cycle to process the stale entry
sleep 10
```

## Expected result (bug present)
The Dragonfly process crashes at `db_slice.cc:1163` when the expiry cycle processes the stale expiry entry for the overwritten key.

## Alternative: Faster reproduction with short TTL
```bash
redis-cli -p 6379 SET mykey "value1" PX 500
redis-cli -p 6379 SET mykey "value2"
sleep 2
redis-cli -p 6379 PING
```
If the process has crashed, PING will fail with a connection error.
