# Setup: Kvrocks #3148

## Project
- **Repository:** https://github.com/apache/kvrocks
- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/3148

## Clone and checkout buggy version
```bash
git clone --recurse-submodules https://github.com/apache/kvrocks.git
cd kvrocks
git checkout 833ae36aa1d17e87be494724689b87e5234286ec~1
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
