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

## Oracle verdict

`./bench.sh reproduce dragonfly-6764-hincrbyfloat-nan` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `HINCRBYFLOAT nonexist field nan` followed by `HRANDFIELD nonexist 1`, the Dragonfly process has exited (crashed) or no longer answers `PING`. A worktree that does not build, or a Dragonfly server that does not answer `PING` within 60 s of starting, is also FAIL.
- **PASS** (exit 0): Dragonfly is still running and answers `PING` with `PONG` after the trigger (the replies to the two commands are not checked).
- **ERROR** (exit 2): `REBUILD.sh` or the built `build-dbg/dragonfly` binary is missing (the case is not set up).
