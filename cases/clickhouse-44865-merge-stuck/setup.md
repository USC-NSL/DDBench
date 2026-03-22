# Setup: ClickHouse — Background Merges Stuck on Replicated Tables

## Project
- **Repository:** https://github.com/ClickHouse/ClickHouse
- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/44865
- **Related:** https://github.com/ClickHouse/ClickHouse/issues/43816

## Option A: Docker (recommended)

Use a version affected by this bug (v22.8 through early v23.x):
```bash
docker pull clickhouse/clickhouse-server:22.8
```

Create a cluster config with 2 replicas using `docker-compose.yml`:
```yaml
version: '3'
services:
  zookeeper:
    image: zookeeper:3.8
    ports:
      - "2181:2181"

  ch-replica1:
    image: clickhouse/clickhouse-server:22.8
    ports:
      - "8123:8123"
      - "9000:9000"
    volumes:
      - ./cluster_config.xml:/etc/clickhouse-server/config.d/cluster.xml
      - ./macros1.xml:/etc/clickhouse-server/config.d/macros.xml
    depends_on:
      - zookeeper

  ch-replica2:
    image: clickhouse/clickhouse-server:22.8
    ports:
      - "8124:8123"
      - "9001:9000"
    volumes:
      - ./cluster_config.xml:/etc/clickhouse-server/config.d/cluster.xml
      - ./macros2.xml:/etc/clickhouse-server/config.d/macros.xml
    depends_on:
      - zookeeper
```

Create `cluster_config.xml`:
```xml
<clickhouse>
    <zookeeper>
        <node>
            <host>zookeeper</host>
            <port>2181</port>
        </node>
    </zookeeper>
    <remote_servers>
        <test_cluster>
            <shard>
                <replica>
                    <host>ch-replica1</host>
                    <port>9000</port>
                </replica>
                <replica>
                    <host>ch-replica2</host>
                    <port>9000</port>
                </replica>
            </shard>
        </test_cluster>
    </remote_servers>
</clickhouse>
```

Create `macros1.xml`:
```xml
<clickhouse>
    <macros>
        <shard>1</shard>
        <replica>replica1</replica>
    </macros>
</clickhouse>
```

Create `macros2.xml`:
```xml
<clickhouse>
    <macros>
        <shard>1</shard>
        <replica>replica2</replica>
    </macros>
</clickhouse>
```

Start the cluster:
```bash
docker-compose up -d
```

## Option B: Build from source

```bash
git clone --recurse-submodules https://github.com/ClickHouse/ClickHouse.git
cd ClickHouse
git checkout v22.8.1.2097-lts
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
ninja clickhouse-server clickhouse-client
```

Deploy two replicas with ZooKeeper and the config above.
