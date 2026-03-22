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

Start master with tiered storage enabled:
```bash
./build-opt/dragonfly --port 6379 --logtostderr --proactor_threads 4 \
  --dbfilename="" --tiered_prefix=/tmp/dragonfly_tiered
```

Start replica:
```bash
./build-opt/dragonfly --port 6380 --logtostderr --proactor_threads 4 \
  --dbfilename=""
```
