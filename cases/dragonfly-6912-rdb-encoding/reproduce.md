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
