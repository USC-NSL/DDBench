# Reproduce: Dragonfly #6856

## Step 1: Start Dragonfly node in cluster mode
```bash
./build-dbg/dragonfly \
  --port 6380 \
  --logtostderr \
  --proactor_threads 1 \
  --dbfilename="" \
  --cluster_mode=yes \
  --cluster_node_id=0000000000000000000000000000000000000000
```

## Step 2: Send the crashing command
In a separate terminal:
```bash
redis-cli -p 6380 DFLYCLUSTER FLUSHSLOTS 16384
```

## Expected result (bug present)
The Dragonfly process in terminal 1 crashes with SIGABRT:
```
F... init.cc:140] Uncaught exception: bitset::set: __position (which is 16384) >= _Nb (which is 16384)
*** SIGABRT received ***
```

## Alternative reproduction
The original issue includes a crash replay archive. Download `crash-000000.tar.gz`
from the issue, then:
```bash
tar xzf crash-000000.tar.gz
cd crash-000000
python3 replay_crash.py crashes 000000
```

## Notes
- The crash is deterministic and triggers on every attempt.
- Any slot ID >= 16384 will trigger the crash (e.g., 16384, 20000, 99999).
- Slot IDs 0–16383 are valid and do not crash.
