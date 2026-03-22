# Setup: ClickHouse Keeper — Segfault on Startup (v22.7)

## Project
- **Repository:** https://github.com/ClickHouse/ClickHouse
- **Language:** C++
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/40571
- **Fix PR:** https://github.com/ClickHouse/ClickHouse/pull/40627

## Option A: Docker (recommended)

Use the specific buggy version of ClickHouse Keeper:
```bash
docker pull clickhouse/clickhouse-keeper:22.7
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
            <raft_logs_level>trace</raft_logs_level>
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
  clickhouse/clickhouse-keeper:22.7
```

## Option B: Build from source

```bash
git clone --recurse-submodules https://github.com/ClickHouse/ClickHouse.git
cd ClickHouse
# Checkout the parent of the fix commit to get the buggy version
git checkout cecdcb50598aad333d8cb784b914a19a567e0b88~1
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
ninja clickhouse-keeper
```

Start the Keeper binary with the config above:
```bash
./build/programs/clickhouse-keeper --config-file=keeper_config.xml
```
