# Reproduce: Dragonfly #6912

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Create a CMS key and DUMP it

```bash
# Create a Count-Min Sketch
redis-cli -p 6379 CMS.INITBYPROB mysketch 0.001 0.01

# Add some items
redis-cli -p 6379 CMS.INCRBY mysketch item1 5 item2 10

# DUMP the key — this triggers the crash
redis-cli -p 6379 DUMP mysketch
```

Alternatively, replay the crash archive from the issue:
```bash
tar xzf crash-000000.tar.gz
cd crash-000000
python3 replay_crash.py crashes 000000
```

## Expected result (bug present)
The Dragonfly process crashes with:
```
F... rdb_save.cc:206] Unknown encoding 0 for type 17
```

## Oracle verdict

`./bench.sh reproduce dragonfly-6912-rdb-encoding` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `CMS.INITBYPROB mysketch 0.001 0.01`, `CMS.INCRBY mysketch item1 5 item2 10` and `DUMP mysketch`, the Dragonfly process has exited (crashed) or no longer answers `PING`. A worktree that does not build, a Dragonfly server that does not answer `PING` within 60 s of starting, or a `CMS.INITBYPROB` that does not return `OK`, is also FAIL.
- **PASS** (exit 0): Dragonfly is still running and answers `PING` with `PONG` after the trigger (the `DUMP` payload is not checked).
- **ERROR** (exit 2): `REBUILD.sh` or the built `build-dbg/dragonfly` binary is missing (the case is not set up).
