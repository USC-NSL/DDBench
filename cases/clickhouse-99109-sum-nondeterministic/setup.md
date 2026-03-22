# Setup: ClickHouse #99109

## Project
- **Repository:** https://github.com/ClickHouse/ClickHouse
- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/99109

## Option A: Docker (recommended)

```bash
docker run -d --name clickhouse-server -p 8123:8123 -p 9000:9000 \
  clickhouse/clickhouse-server:24.12
```

## Option B: Build from source

```bash
git clone https://github.com/ClickHouse/ClickHouse.git
cd ClickHouse
git checkout v24.12.1.1614-stable
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
ninja clickhouse-server clickhouse-client
```

Start the server:
```bash
./build/programs/clickhouse-server --config-file=./programs/server/config.xml
```
