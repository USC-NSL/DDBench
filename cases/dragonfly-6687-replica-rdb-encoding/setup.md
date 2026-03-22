# Setup: Dragonfly #6687

## Project
- **Repository:** https://github.com/dragonflydb/dragonfly
- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6687

## Clone and checkout buggy version
```bash
git clone --recurse-submodules https://github.com/dragonflydb/dragonfly.git
cd dragonfly
git checkout 8347cd80192a7be967a3983a6a55a10525915015~1
git submodule update --init --recursive
```

## Build
```bash
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Release
```

## Deploy: Master + Replica with tiered storage

Start master with tiered storage enabled. The following flags are critical for reliable reproduction:
- `--tiered_prefix` enables tiered storage
- `--tiered_offload_threshold=1.0` forces all data to be offloaded to disk
- `--serialization_max_chunk_size=64000` uses smaller serialization chunks that expose the encoding bug
- `--maxmemory=512mb` triggers memory pressure that forces tiered offload

```bash
./build-opt/dragonfly --port 6379 --logtostderr --proactor_threads 4 \
  --dbfilename="" \
  --tiered_prefix=/tmp/dragonfly_tiered \
  --tiered_offload_threshold=1.0 \
  --serialization_max_chunk_size=64000 \
  --maxmemory=512mb
```

Start replica:
```bash
./build-opt/dragonfly --port 6380 --logtostderr --proactor_threads 4 \
  --dbfilename=""
```
