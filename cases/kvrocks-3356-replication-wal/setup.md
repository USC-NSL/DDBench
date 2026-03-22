# Setup: Kvrocks #3356

## Project
- **Repository:** https://github.com/apache/kvrocks
- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/3356

## Clone and checkout buggy version
```bash
git clone https://github.com/apache/kvrocks.git
cd kvrocks
git checkout 559a667bef223a07fea350a27168e91fe0a74601~1
git submodule update --init --recursive
```

## Build
```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

## Deploy: Master + Replica

Create master config `master.conf`:
```
bind 0.0.0.0
port 6666
dir /tmp/kvrocks-master
```

Create replica config `replica.conf`:
```
bind 0.0.0.0
port 6667
dir /tmp/kvrocks-replica
slaveof 127.0.0.1 6666
```

Start master and replica:
```bash
mkdir -p /tmp/kvrocks-master /tmp/kvrocks-replica
./build/kvrocks -c master.conf &
./build/kvrocks -c replica.conf &
```
