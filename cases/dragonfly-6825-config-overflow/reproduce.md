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
