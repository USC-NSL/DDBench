# Setup: Dragonfly — Cluster CONFIG Overflow Crash

## Project
- **Repository:** https://github.com/dragonflydb/dragonfly
- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6825

## Prerequisites
- Linux (x86_64 or aarch64)
- CMake >= 3.16, Ninja, GCC >= 11 or Clang >= 14
- `redis-cli`, Python 3

## Clone and checkout buggy version
```bash
git clone --recurse-submodules https://github.com/dragonflydb/dragonfly.git
cd dragonfly
git checkout 4b16da4d2e80eafc57ecb5fef511a9d49afe5c54~1
git submodule update --init --recursive
```

## Build
```bash
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
```
