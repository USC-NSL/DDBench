# Reproduce: Dragonfly #6909

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Download and extract crash archive
Download the crash archive from the GitHub issue:
```bash
# From https://github.com/dragonflydb/dragonfly/issues/6909
# Download crash-000000.tar.gz attachment
tar xzf crash-000000.tar.gz
cd crash-000000
```

## Step 3: Replay the crash
```bash
python3 replay_crash.py crashes 000000
```

Alternatively, reproduce manually by creating a search index with a NUMERIC field and inserting a document with a non-finite value:
```bash
redis-cli -p 6379 FT.CREATE myidx ON HASH PREFIX 1 doc: SCHEMA score NUMERIC
redis-cli -p 6379 HSET doc:1 score inf
redis-cli -p 6379 FT.SEARCH myidx "*"
```

## Expected result (bug present)
The Dragonfly process crashes.

## Oracle verdict

`./bench.sh reproduce dragonfly-6909-search-nonfinite` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `FT.CREATE myidx ON HASH PREFIX 1 doc: SCHEMA score NUMERIC`, `HSET doc:1 score inf` and `FT.SEARCH myidx '*'`, the Dragonfly process has exited (crashed) or no longer answers `PING`. A worktree that does not build, a Dragonfly server that does not answer `PING` within 60 s of starting, or an `FT.CREATE` that does not return `OK`, is also FAIL.
- **PASS** (exit 0): Dragonfly is still running and answers `PING` with `PONG` after the trigger (the replies to `HSET` and `FT.SEARCH` are not checked).
- **ERROR** (exit 2): `REBUILD.sh` or the built `build-dbg/dragonfly` binary is missing (the case is not set up).
