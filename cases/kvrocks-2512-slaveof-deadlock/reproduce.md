# Reproduce: Kvrocks #2512

## Prerequisites
- Run inside `./bench.sh shell kvrocks-2512-slaveof-deadlock`, from `/workspace/src`; `./bench.sh setup` has built Kvrocks at `build/kvrocks`.
- `redis-cli` is available in the image.

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

## Oracle verdict

`./bench.sh reproduce kvrocks-2512-slaveof-deadlock` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): with the oracle's temporary 2 s race-widening sleep compiled in (see Reproduction Strategy), a second `SLAVEOF` sent 0.5 s after a `SLAVEOF` that forces a full sync does not return within 10 s, or the replica then answers `PING` with neither `PONG` nor `LOADING` within 5 s (up to 3 attempts), or it never answers `PONG` in the final check (15 tries, `LOADING` replies tolerated). A worktree that does not build with the instrumentation applied, or a master or replica that does not answer `PING` within 30 s of starting, is also FAIL.
- **PASS** (exit 0): no attempt hangs and the replica answers `PING` with `PONG` in the final check.
- **ERROR** (exit 2): `REBUILD.sh` or the built `build/kvrocks` binary is missing, or the oracle cannot instrument `src/server/server.cc` because its anchor log line is not found.
