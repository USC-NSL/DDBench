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
