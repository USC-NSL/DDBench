# Reproduce: Kvrocks #3208

## Prerequisites
- Run inside `./bench.sh shell kvrocks-3208-replication-watermark`, from `/workspace/src`; `./bench.sh setup` has built Kvrocks at `build/kvrocks`.
- `redis-cli` is available in the image.

## Step 1: Start master
```bash
./build/kvrocks -c master.conf &
# master.conf: bind 0.0.0.0, port 13208, dir ./master-data, log-dir ./master-data
```

## Step 2: Start replica connected to master
```bash
./build/kvrocks -c replica.conf &
# replica.conf: bind 0.0.0.0, port 13209, dir ./replica-data, log-dir ./replica-data, slaveof 127.0.0.1 13208
```

## Step 3: Wait for full sync to complete
```bash
# Poll until replica reports master_link_status:up
redis-cli -p 13209 INFO replication | grep master_link_status
```

## Step 4: Write a large value to master to trigger a high-water mark
```bash
# Write a 16KB value
redis-cli -p 13208 SET large_key $(python3 -c "print('a'*16384)")
```

## Step 5: Wait briefly for the large value to propagate
```bash
sleep 1
```

## Step 6: Write a small value to master
```bash
redis-cli -p 13208 SET small_key small_value
```

## Step 7: Check if small value appears on replica
```bash
# Poll replica for the small key
redis-cli -p 13209 GET small_key
```

## Expected result (bug present)
The small value does NOT appear on the replica within several seconds. The replica is stalled waiting for more data to arrive before processing the replication stream, despite the connection being healthy. The value will eventually appear only after enough PINGs or additional data accumulate to satisfy the stuck threshold.

## Oracle verdict

`./bench.sh reproduce kvrocks-3208-replication-watermark` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after a 16 KB value is written on the master and replicated, a following `SET small_key small_value` on the master is not readable on the replica within 5 s (50 polls, 0.1 s apart). A worktree that does not build, a master that does not answer `PING`, a replica that does not report `master_link_status:up` within about 30 s, or a baseline key that never reaches the replica, is also FAIL.
- **PASS** (exit 0): `GET small_key` on the replica returns `small_value` within 5 s.
- **ERROR** (exit 2): `REBUILD.sh` or the built `build/kvrocks` binary is missing, or the master rejects the 16 KB `SET` (trigger not established).
