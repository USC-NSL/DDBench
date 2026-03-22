# Setup: ClickHouse — Predicate Pushdown Incorrectly Rewrites Distributed IN Subqueries

## Project
- **Repository:** https://github.com/ClickHouse/ClickHouse
- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/29332

## Option A: Docker (recommended)

```bash
docker pull clickhouse/clickhouse-server:21.10
```

Create a cluster config file `cluster_config.xml`. **Note:** ClickHouse v21.10 uses `<yandex>` as the XML root element, not `<clickhouse>` (which was introduced in later versions):
```xml
<yandex>
    <remote_servers>
        <test_cluster>
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
        </test_cluster>
    </remote_servers>
</yandex>
```

Start two ClickHouse instances:
```bash
# Shard 1
docker run -d --name ch-shard1 --network host \
  -v $(pwd)/cluster_config.xml:/etc/clickhouse-server/config.d/cluster.xml \
  -e CLICKHOUSE_HTTP_PORT=8123 -e CLICKHOUSE_TCP_PORT=9000 \
  clickhouse/clickhouse-server:21.10

# Shard 2
docker run -d --name ch-shard2 --network host \
  -v $(pwd)/cluster_config.xml:/etc/clickhouse-server/config.d/cluster.xml \
  -e CLICKHOUSE_HTTP_PORT=8124 -e CLICKHOUSE_TCP_PORT=9001 \
  clickhouse/clickhouse-server:21.10
```

## Option B: Build from source

```bash
git clone --recurse-submodules https://github.com/ClickHouse/ClickHouse.git
cd ClickHouse
git checkout v21.10.1.8013-stable
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
ninja clickhouse-server clickhouse-client
```

Start two instances on ports 9000 and 9001 with the cluster config above.
