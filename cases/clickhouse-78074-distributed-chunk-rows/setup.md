# Setup: ClickHouse — Invalid Number of Rows in Chunk with Distributed JOIN

## Project
- **Repository:** https://github.com/ClickHouse/ClickHouse
- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/78074

## Option A: Docker (recommended)

```bash
docker pull clickhouse/clickhouse-server:25.2.1.3085
```

Create a cluster config file `cluster_config.xml`:
```xml
<clickhouse>
    <remote_servers>
        <test_cluster>
            <shard>
                <replica>
                    <host>localhost</host>
                    <port>9000</port>
                </replica>
            </shard>
        </test_cluster>
    </remote_servers>
</clickhouse>
```

Start ClickHouse:
```bash
docker run -d --name ch-node --network host \
  -v $(pwd)/cluster_config.xml:/etc/clickhouse-server/config.d/cluster.xml \
  clickhouse/clickhouse-server:25.2.1.3085
```

Verify:
```bash
docker exec ch-node clickhouse-client -q "SELECT version()"
```

## Option B: Build from source

```bash
git clone --recurse-submodules https://github.com/ClickHouse/ClickHouse.git
cd ClickHouse
# Checkout parent of fix commit to get the buggy version
git checkout 1b768fe2b4695dbb5d6b7534fe881e812852cb45~1
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
ninja clickhouse-server clickhouse-client
```

Start the server with the cluster config above.
