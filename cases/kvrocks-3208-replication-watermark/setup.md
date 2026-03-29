# Setup: Kvrocks #3208

## Project
- **Repository:** https://github.com/apache/kvrocks
- **Language:** C++
- **Issue:** https://github.com/apache/kvrocks/issues/3208

## Clone and checkout buggy version
```bash
git clone --recurse-submodules https://github.com/apache/kvrocks.git
cd kvrocks
git checkout 54929cd01603f9a19cd3b700b8b4da1683e4eda9~1
git submodule update --init --recursive
```

## Build
```bash
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

## Deploy
Start a master and replica instance:

**Master config (master.conf):**
```
bind 0.0.0.0
port 13208
dir ./master-data
log-dir ./master-data
```

**Replica config (replica.conf):**
```
bind 0.0.0.0
port 13209
dir ./replica-data
log-dir ./replica-data
slaveof 127.0.0.1 13208
```

```bash
mkdir -p master-data replica-data
./build/kvrocks -c master.conf &
./build/kvrocks -c replica.conf &
```
