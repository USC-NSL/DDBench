# Reproduce: Dragonfly #6907

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Trigger the bug
```bash
# Create index expecting 4-dim vector
redis-cli -p 6379 FT.CREATE idx ON HASH PREFIX 1 doc: SCHEMA vec VECTOR FLAT 6 TYPE FLOAT32 DIM 4 DISTANCE_METRIC L2
# Insert doc with wrong size (2 dims instead of 4)
redis-cli -p 6379 HSET doc:1 vec "\x00\x00\x80\x3f\x00\x00\x00\x40"
# Search triggers crash
redis-cli -p 6379 FT.SEARCH idx '*'
```

## Expected result (bug present)
The Dragonfly process crashes.

## Oracle verdict

`./bench.sh reproduce dragonfly-6907-ftsearch-vector-crash` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `FT.CREATE` of an HNSW vector index (`FLOAT32`, `DIM 4`), `HSET doc:1 vec` with a 5-byte value and `FT.SEARCH idx '*'`, the Dragonfly process has exited (crashed) or no longer answers `PING`. A worktree that does not build, a Dragonfly server that does not answer `PING` within 60 s of starting, or an `FT.CREATE` that does not return `OK`, is also FAIL.
- **PASS** (exit 0): Dragonfly is still running and answers `PING` with `PONG` after the trigger (the search reply is not checked).
- **ERROR** (exit 2): `REBUILD.sh` or the built `build-dbg/dragonfly` binary is missing (the case is not set up).
