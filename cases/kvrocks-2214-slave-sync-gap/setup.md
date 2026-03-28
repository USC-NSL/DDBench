# Setup: Kvrocks #2214

## Project
- **Repository:** https://github.com/apache/kvrocks
- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/2214

## Clone and checkout buggy version
```bash
git clone --recurse-submodules https://github.com/apache/kvrocks.git
cd kvrocks
git checkout 7e1b797920517edf9c798cd4b440789b524d7956~1
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
- `redis-cli` (from redis-tools package)

## Deploy: Master + Slave

Create master config `master.conf`:
```
bind 0.0.0.0
port 12214
dir /tmp/kvrocks-2214-master
log-dir /tmp/kvrocks-2214-master/logs
repl-namespace-enabled yes
```

Create slave config `slave.conf`:
```
bind 0.0.0.0
port 12215
dir /tmp/kvrocks-2214-slave
log-dir /tmp/kvrocks-2214-slave/logs
repl-namespace-enabled yes
slaveof 127.0.0.1 12214
```

Start master and slave:
```bash
mkdir -p /tmp/kvrocks-2214-master/logs /tmp/kvrocks-2214-slave/logs
./build/kvrocks -c master.conf &
./build/kvrocks -c slave.conf &
```
