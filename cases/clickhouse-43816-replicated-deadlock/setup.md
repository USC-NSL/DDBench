# Setup: ClickHouse #43816

## Project
- **Repository:** https://github.com/ClickHouse/ClickHouse
- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/43816

## Deploy: Docker Compose cluster with ZooKeeper

Create `docker-compose.yml`:
```yaml
version: "3"
services:
  zookeeper:
    image: zookeeper:3.8
    ports:
      - "2181:2181"

  clickhouse1:
    image: clickhouse/clickhouse-server:22.10
    ports:
      - "9001:9000"
      - "8124:8123"
    volumes:
      - ./config.xml:/etc/clickhouse-server/config.d/cluster.xml
    depends_on:
      - zookeeper

  clickhouse2:
    image: clickhouse/clickhouse-server:22.10
    ports:
      - "9002:9000"
      - "8125:8123"
    volumes:
      - ./config.xml:/etc/clickhouse-server/config.d/cluster.xml
    depends_on:
      - zookeeper
```

Create `config.xml`:
```xml
<clickhouse>
    <remote_servers>
        <test_cluster>
            <shard>
                <replica>
                    <host>clickhouse1</host>
                    <port>9000</port>
                </replica>
                <replica>
                    <host>clickhouse2</host>
                    <port>9000</port>
                </replica>
            </shard>
        </test_cluster>
    </remote_servers>
    <zookeeper>
        <node>
            <host>zookeeper</host>
            <port>2181</port>
        </node>
    </zookeeper>
    <macros>
        <shard>01</shard>
    </macros>
</clickhouse>
```

Note: set `<replica>` macro per node (e.g., `01` for clickhouse1, `02` for clickhouse2) via environment or separate config files.

```bash
docker-compose up -d
```

## Build from source (version 22.10)
```bash
git clone https://github.com/ClickHouse/ClickHouse.git
cd ClickHouse
git checkout v22.10.1.1877-stable
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
ninja clickhouse-server clickhouse-client
```
