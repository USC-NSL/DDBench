# Reproduce: Dragonfly #6614

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Trigger the bug
```bash
redis-cli -p 6379 MULTI
redis-cli -p 6379 MONITOR
redis-cli -p 6379 MONITOR
redis-cli -p 6379 EXEC
```
Or in a single redis-cli session:
```
MULTI
MONITOR
MONITOR
EXEC
```

## Expected result (bug present)
The Dragonfly process crashes.

## Oracle verdict

`./bench.sh reproduce dragonfly-6614-monitor-multiexec` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after 100 rounds of 10 concurrent connections that each send `MULTI`, `MONITOR`, `MONITOR`, `EXEC` as one pipeline, the Dragonfly process has exited (crashed) or no longer answers `PING`. A worktree that does not build, or a Dragonfly server that does not answer `PING` within 60 s of starting, is also FAIL.
- **PASS** (exit 0): Dragonfly is still running and answers `PING` with `PONG` after the trigger.
- **ERROR** (exit 2): `REBUILD.sh` or the built `build-dbg/dragonfly` binary is missing (the case is not set up), or the Python client that sends the pipelines fails.
