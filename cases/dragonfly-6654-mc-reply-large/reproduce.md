# Reproduce: Dragonfly #6654

## Step 1: Start Dragonfly with memcached port and large bulk length
```bash
./build-dbg/dragonfly --port 6379 --memcached_port=11211 --max_bulk_len=1048576 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Download and replay crash archive
Download the crash archive from the GitHub issue:
```bash
# From https://github.com/dragonflydb/dragonfly/issues/6654
tar xzf crash-000000.tar.gz
cd crash-000000
python3 replay_crash.py crashes 000000
```

Alternatively, reproduce manually:
```bash
# Store a large value via Redis protocol
redis-cli -p 6379 SET bigkey "$(python3 -c "print('A' * 8000)")"

# Retrieve via memcached meta get — this triggers the crash
echo -e "mg bigkey v\r\nquit\r\n" | nc 127.0.0.1 11211
```

## Expected result (bug present)
The Dragonfly process crashes with a buffer overflow assertion.
