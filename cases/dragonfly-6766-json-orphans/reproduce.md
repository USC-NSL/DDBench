# Reproduce: Dragonfly #6766

## Step 1: Start Dragonfly
```bash
./build-dbg/dragonfly --port 6379 --logtostderr --proactor_threads 1 --dbfilename=""
```

## Step 2: Rapid JSON.SET + DEL cycles on nested structures

```bash
# Run a loop that creates and deletes nested JSON structures
for i in $(seq 1 1000); do
  redis-cli -p 6379 JSON.SET mykey '.' '{"a":{"b":{"c":"val","d":[1,2,3]},"e":{"f":"val2"}}}'
  redis-cli -p 6379 JSON.SET mykey '$.a.b' '{"new":"data","nested":{"x":1}}'
  redis-cli -p 6379 DEL mykey
done
```

Or download and replay the crash archive from the issue:
```bash
tar xzf crash-000000.tar.gz
cd crash-000000
python3 replay_crash.py crashes 000000
```

## Expected result (bug present)
The Dragonfly process crashes at `json_family.cc:99` due to corrupted memory tracking from orphaned JSON objects.
