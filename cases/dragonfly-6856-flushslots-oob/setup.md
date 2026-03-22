# Setup: Dragonfly — Cluster FLUSHSLOTS OOB Crash

## Project
- **Repository:** https://github.com/dragonflydb/dragonfly
- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6856

## Prerequisites
- Linux (x86_64 or aarch64)
- CMake >= 3.16, Ninja, GCC >= 11 or Clang >= 14
- `redis-cli` (from redis-tools or redis package)

## Clone and checkout buggy version
```bash
git clone --recurse-submodules https://github.com/dragonflydb/dragonfly.git
cd dragonfly
git checkout c79bbe0c646c1bce47f76168dbe813951aecd8ce~1
git submodule update --init --recursive
```

## Build
```bash
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
# Binary will be at ./build-dbg/dragonfly
# Alternatively for release:
# ./helio/blaze.sh -DCMAKE_BUILD_TYPE=Release
```

## Verify build
```bash
./build-dbg/dragonfly --version
```

The system is now ready to run in cluster mode. See reproduce.md for deployment steps.
