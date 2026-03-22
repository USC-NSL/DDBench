# Setup: Dragonfly #6619

## Project
- **Repository:** https://github.com/dragonflydb/dragonfly
- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6619

## Clone and checkout buggy version
```bash
git clone --recurse-submodules https://github.com/dragonflydb/dragonfly.git
cd dragonfly
git checkout 761387a51433a5becb06db2ac7bf7e9f18b832d2~1
git submodule update --init --recursive
```

## Build
```bash
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
