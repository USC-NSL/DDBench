# Reproduce: Dragonfly #6619

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Trigger the bug
```bash
redis-cli -p 6379 EVALSHA "" 0
```

## Expected result (bug present)
The Dragonfly process crashes.

## Oracle verdict

`./bench.sh reproduce dragonfly-6619-evalsha-empty` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `EVALSHA "" 0`, the Dragonfly process has exited (crashed) or no longer answers `PING`. A worktree that does not build, or a Dragonfly server that does not answer `PING` within 60 s of starting, is also FAIL.
- **PASS** (exit 0): Dragonfly is still running and answers `PING` with `PONG` after the trigger (the reply to `EVALSHA` itself is not checked).
- **ERROR** (exit 2): `REBUILD.sh` or the built `build-dbg/dragonfly` binary is missing (the case is not set up).
