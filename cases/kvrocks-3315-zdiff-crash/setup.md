# Setup: Kvrocks — ZDIFF Crash

## Project
- **Repository:** https://github.com/apache/kvrocks
- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/3315

## Prerequisites
- Linux or macOS
- CMake >= 3.16, GCC >= 7 or Clang
- `redis-cli`

## Clone and checkout buggy version
```bash
git clone https://github.com/apache/kvrocks.git
cd kvrocks
git checkout c2c5d094d4335c4951f88e7de319d78e1bf5b3b8~1
```

## Build
```bash
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## Verify
```bash
./build/kvrocks --version
```
