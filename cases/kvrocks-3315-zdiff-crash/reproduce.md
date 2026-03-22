# Reproduce: Kvrocks #3315

## Step 1: Start Kvrocks
```bash
./bin/kvrocks -p 6666 --dir /tmp/kvrocks_data
```

## Step 2: Send the crashing command
```bash
redis-cli -p 6666 ZDIFF 0 a
```

## Expected result (bug present)
The kvrocks process crashes immediately.
