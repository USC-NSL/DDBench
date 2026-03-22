# Setup: Dragonfly #6909

## Project
- **Repository:** https://github.com/dragonflydb/dragonfly
- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6909

## Clone and checkout buggy version
```bash
git clone --recurse-submodules https://github.com/dragonflydb/dragonfly.git
cd dragonfly
git checkout 1c38bb63d2824080430d6d25e5a6fe6d714a2882~1
git submodule update --init --recursive
```

## Build
```bash
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
