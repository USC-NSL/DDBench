# Reproduce: Dragonfly #6761

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --memcached_port=11211 --logtostderr --proactor_threads 1 --dbfilename="" --max_bulk_len=1048576
```

## Step 2: Trigger the bug

Send pipelined memcached commands where a `get` precedes a `version` or `stats` command:
```bash
printf "get nokey\r\nversion\r\n" | nc 127.0.0.1 11211
```

Or send a mix of set/get with stats:
```bash
printf "set testkey 0 0 5\r\nhello\r\nget testkey\r\nstats\r\n" | nc 127.0.0.1 11211
```

Alternatively, download the crash archive from the issue and replay:
```bash
tar xzf crash-000000.tar.gz
cd crash-000000
python3 replay_crash.py crashes 000000 127.0.0.1 11211
```

## Expected result (bug present)
The Dragonfly process crashes with SIGABRT. The crash occurs in `Connection::ExecuteMCBatch()` because `STATS` and `VERSION` commands return `WOULD_BLOCK` which is not handled in the pipeline batch execution path.

## Oracle verdict

`./bench.sh reproduce dragonfly-6761-mc-pipeline-crash` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `get nokey` and `version` are sent as one pipeline to the memcached port, the Dragonfly process has exited (crashed) or no longer answers `PING`. A worktree that does not build, or a Dragonfly server that does not answer `PING` within 60 s of starting, is also FAIL.
- **PASS** (exit 0): Dragonfly is still running and answers `PING` with `PONG` after the trigger (the memcached replies are not checked).
- **ERROR** (exit 2): `REBUILD.sh` or the built `build-dbg/dragonfly` binary is missing (the case is not set up).
