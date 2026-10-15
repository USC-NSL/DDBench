# Reproduce: Kvrocks #2214

## Prerequisites
Run inside `./bench.sh shell kvrocks-2214-slave-sync-gap`, from `/workspace/src` (the binary is `build/kvrocks`). Create the master and slave configs, both with `repl-namespace-enabled yes`:

```bash
cat > master.conf <<'EOF'
bind 0.0.0.0
port 12214
dir /tmp/kvrocks-2214-master
log-dir /tmp/kvrocks-2214-master/logs
repl-namespace-enabled yes
EOF

cat > slave.conf <<'EOF'
bind 0.0.0.0
port 12215
dir /tmp/kvrocks-2214-slave
log-dir /tmp/kvrocks-2214-slave/logs
repl-namespace-enabled yes
slaveof 127.0.0.1 12214
EOF

mkdir -p /tmp/kvrocks-2214-master/logs /tmp/kvrocks-2214-slave/logs
```

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

## Oracle verdict

`./bench.sh reproduce kvrocks-2214-slave-sync-gap` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after the replica (cluster mode, `repl-namespace-enabled yes`) is stopped, the master runs `SET k0 v1` and `HSET k2 f0 v0 f1 v1`, and the replica is restarted and reconnected, the replica still returns a stale `k0` or a missing or wrong `k2` hash. A worktree that does not build, a master or replica that does not answer `PING` within 30 s of starting, a replication link that does not report `master_link_status:up` within 60 s, or an initial `k0 = v0` that never reaches the replica, is also FAIL.
- **PASS** (exit 0): after the restart the replica returns `k0 = v1` and the `k2` fields `f0 = v0` and `f1 = v1`.
- **ERROR** (exit 2): `REBUILD.sh` or the built `build/kvrocks` binary is missing (the case is not set up).
