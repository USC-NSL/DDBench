# Setup: Kvrocks #2520

## Project
- **Repository:** https://github.com/apache/kvrocks
- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/2520

## Clone and checkout buggy version
```bash
git clone --recurse-submodules https://github.com/apache/kvrocks.git
cd kvrocks
git checkout a29df097dd23c36a749e5c616f4d1cae1051e853~1
git submodule update --init --recursive
```

## Build
```bash
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

The binary is at `build/kvrocks`.

## Dependencies
- CMake 3.16+
- C++17 compiler
- RocksDB (bundled as submodule)
