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

## Oracle verdict

`./bench.sh reproduce dragonfly-6753-populate-sigfpe` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `DEBUG POPULATE 100 prefix 0` (value size 0), the Dragonfly process has exited (crashed) or no longer answers `PING`. A worktree that does not build, or a Dragonfly server that does not answer `PING` within 60 s of starting, is also FAIL.
- **PASS** (exit 0): Dragonfly is still running and answers `PING` with `PONG` after the trigger (the reply to `DEBUG POPULATE` itself is not checked).
- **ERROR** (exit 2): `REBUILD.sh` or the built `build-dbg/dragonfly` binary is missing (the case is not set up).
