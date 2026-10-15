# Reproduce: Dragonfly #6825

## Step 1: Start two Dragonfly nodes in cluster mode
Terminal 0:
```bash
./build-dbg/dragonfly --port 6380 --logtostderr --proactor_threads 1 --dbfilename="" \
    --cluster_mode=yes --cluster_node_id=0000000000000000000000000000000000000000
```

Terminal 1:
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename="" \
    --cluster_mode=yes --cluster_node_id=1111111111111111111111111111111111111111 --hz=0
```

## Step 2: Replay the crash
Download `crash-000000.tar.gz` from the GitHub issue, then:
```bash
tar xzf crash-000000.tar.gz
cd crash-000000
python3 replay_crash.py crashes 000000
```

## Expected result (bug present)
One of the Dragonfly processes crashes with SIGABRT and a check failure message.

## Oracle verdict

`./bench.sh reproduce dragonfly-6825-config-overflow` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `DFLYCLUSTER CONFIG` with a slot range whose `end` is `1E383`, sent to a node started with `--cluster_mode=yes`, the Dragonfly process has exited (crashed) or no longer answers `PING`. A worktree that does not build, or a Dragonfly server that does not answer `PING` within 60 s of starting, is also FAIL.
- **PASS** (exit 0): Dragonfly is still running and answers `PING` with `PONG` after the trigger (the reply to `DFLYCLUSTER CONFIG` itself is not checked).
- **ERROR** (exit 2): `REBUILD.sh` or the built `build-dbg/dragonfly` binary is missing (the case is not set up).
