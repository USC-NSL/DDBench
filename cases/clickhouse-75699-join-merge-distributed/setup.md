# Setup: ClickHouse — LOGICAL_ERROR on JOIN with Merge over Distributed Table

## Project
- **Repository:** https://github.com/ClickHouse/ClickHouse
- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/75699

## Option A: Docker (recommended)

**Note:** The bug was introduced in the 25.2 development branch. Use version `25.2.1.3085` (not `25.1.3.23` which does not contain the buggy code path).

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

Start a ClickHouse instance:
```bash
docker run -d --name ch-node --network host \
  -v $(pwd)/cluster_config.xml:/etc/clickhouse-server/config.d/cluster.xml \
  clickhouse/clickhouse-server:25.2.1.3085
```

Verify it is running:
```bash
docker exec ch-node clickhouse-client -q "SELECT version()"
```

## Option B: Build from source

```bash
git clone --recurse-submodules https://github.com/ClickHouse/ClickHouse.git
cd ClickHouse
# Checkout parent of fix commit to get the buggy version
git checkout 9334d08f0c942a7402e88f3929f3252eb032722d~1
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
ninja clickhouse-server clickhouse-client
```

Start the server with the cluster config above and connect via `clickhouse-client`.
