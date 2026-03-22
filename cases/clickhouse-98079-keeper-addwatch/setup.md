# Setup: ClickHouse Keeper — Client Disconnect on addWatch()

## Project
- **Repository:** https://github.com/ClickHouse/ClickHouse
- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/98079
- **Fix PR:** https://github.com/ClickHouse/ClickHouse/pull/98499

## Option A: Docker (recommended)

Use a version before the fix:
```bash
docker pull clickhouse/clickhouse-keeper:25.3
```

Create a Keeper config file `keeper_config.xml`:
```xml
<clickhouse>
    <keeper_server>
        <tcp_port>2181</tcp_port>
        <server_id>1</server_id>
        <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
        <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>
        <coordination_settings>
            <operation_timeout_ms>10000</operation_timeout_ms>
            <session_timeout_ms>30000</session_timeout_ms>
        </coordination_settings>
        <raft_configuration>
            <server>
                <id>1</id>
                <hostname>localhost</hostname>
                <port>9234</port>
            </server>
        </raft_configuration>
    </keeper_server>
</clickhouse>
```

Start Keeper:
```bash
docker run -d --name keeper --network host \
  -v $(pwd)/keeper_config.xml:/etc/clickhouse-keeper/keeper_config.xml \
  clickhouse/clickhouse-keeper:25.3
```

## Option B: Build from source

```bash
git clone --recurse-submodules https://github.com/ClickHouse/ClickHouse.git
cd ClickHouse
# Checkout the parent of the fix commit to get the buggy version
git checkout 3515972fbc064f7b62c963c8e25969053a6a38c2~1
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
ninja clickhouse-keeper
```

## Java ZooKeeper client setup

The bug is triggered by Apache Curator (Java ZooKeeper client). Install:
```bash
# Requires Java 11+
# Using Maven project with dependencies:
# org.apache.curator:curator-recipes:5.5.0
# org.apache.zookeeper:zookeeper:3.8.4
```

Or use the `zkCli.sh` from Apache ZooKeeper distribution for basic testing:
```bash
wget https://archive.apache.org/dist/zookeeper/zookeeper-3.8.4/apache-zookeeper-3.8.4-bin.tar.gz
tar xzf apache-zookeeper-3.8.4-bin.tar.gz
```
