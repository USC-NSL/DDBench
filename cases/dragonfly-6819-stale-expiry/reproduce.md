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

## Oracle verdict

`./bench.sh reproduce dragonfly-6819-stale-expiry` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `LPUSH mylist 3 2 1`, `PEXPIRE mylist 500` and `SORT mylist STORE mylist`, followed by about 3 s of waiting past the original expiry, the Dragonfly process has exited (crashed) or no longer answers `PING`. A worktree that does not build, a Dragonfly server that does not answer `PING` within 60 s of starting, or an `LPUSH`/`PEXPIRE` that does not return `3`/`1`, is also FAIL.
- **PASS** (exit 0): Dragonfly is still running and answers `PING` with `PONG` after the trigger (the contents and TTL of `mylist` are not checked).
- **ERROR** (exit 2): `REBUILD.sh` or the built `build-dbg/dragonfly` binary is missing (the case is not set up).
