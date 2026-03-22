# Setup: Kvrocks #3339

## Project
- **Repository:** https://github.com/apache/kvrocks
- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/3339

## Clone and checkout buggy version
```bash
git clone https://github.com/apache/kvrocks.git
cd kvrocks
git checkout 25216331bce6f9e97b945aad1cbb04e2db261287~1
git submodule update --init --recursive
```

## Build
```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## Deploy
```bash
mkdir -p /tmp/kvrocks-data
./build/kvrocks --port 6666 --dir /tmp/kvrocks-data --log-dir /tmp/kvrocks-logs
```
