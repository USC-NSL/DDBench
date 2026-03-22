# Setup: ClickHouse #92375

## Project
- **Repository:** https://github.com/ClickHouse/ClickHouse
- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/92375

## Option A: Docker (recommended)

```bash
docker pull clickhouse/clickhouse-server:24.12
```

Create a cluster config file `cluster_config.xml`:
```xml
<clickhouse>
    <remote_servers>
        <test_cluster_two_shards>
            <shard>
                <replica>
                    <host>localhost</host>
                    <port>9000</port>
                </replica>
            </shard>
            <shard>
                <replica>
                    <host>localhost</host>
                    <port>9001</port>
                </replica>
            </shard>
        </test_cluster_two_shards>
    </remote_servers>
</clickhouse>
```

Start two ClickHouse instances:
```bash
# Shard 1
docker run -d --name ch-shard1 --network host \
  -v $(pwd)/cluster_config.xml:/etc/clickhouse-server/config.d/cluster.xml \
  -e CLICKHOUSE_HTTP_PORT=8123 -e CLICKHOUSE_TCP_PORT=9000 \
  clickhouse/clickhouse-server:24.12

# Shard 2
docker run -d --name ch-shard2 --network host \
  -v $(pwd)/cluster_config.xml:/etc/clickhouse-server/config.d/cluster.xml \
  -e CLICKHOUSE_HTTP_PORT=8124 -e CLICKHOUSE_TCP_PORT=9001 \
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

Configure the two-shard cluster in `/etc/clickhouse-server/config.d/cluster.xml` with the XML above and start two instances on ports 9000 and 9001.
