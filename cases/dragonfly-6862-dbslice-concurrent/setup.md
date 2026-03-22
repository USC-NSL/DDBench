# Setup: Dragonfly — Crash in db_slice.cc During Concurrent Operations in Cluster Mode

## Project
- **Repository:** https://github.com/dragonflydb/dragonfly
- **Language:** C++
- **Issue:** https://github.com/dragonflydb/dragonfly/issues/6862

## Prerequisites
- Linux (x86_64 or aarch64)
- CMake >= 3.16, Ninja, GCC >= 11 or Clang >= 14
- `redis-cli` and `redis-benchmark` (from redis-tools or redis package)

## Clone and checkout buggy version

```bash
git clone --recurse-submodules https://github.com/dragonflydb/dragonfly.git
cd dragonfly
# Checkout a version affected by the bug (before the fix)
git log --oneline --all | head -20  # Find a commit before the fix
git submodule update --init --recursive
```

## Build

```bash
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Debug
# Binary will be at ./build-dbg/dragonfly
```

For release build (better performance for stress testing):
```bash
./helio/blaze.sh -DCMAKE_BUILD_TYPE=Release
# Binary will be at ./build-opt/dragonfly
```

## Verify build

```bash
./build-dbg/dragonfly --version
```

The system is now ready to run in cluster mode. See reproduce.md for deployment steps.
