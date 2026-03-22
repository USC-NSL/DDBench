# Reproduce: ClickHouse #40571

## Prerequisites
- Docker installed, or ClickHouse Keeper built from source at the buggy commit (see setup.md)

## Step 1: Start Keeper using Docker

```bash
# Create the Keeper config
cat > keeper_config.xml <<'EOF'
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
EOF

# Start Keeper
docker run --name keeper --network host \
  -v $(pwd)/keeper_config.xml:/etc/clickhouse-keeper/keeper_config.xml \
  clickhouse/clickhouse-keeper:22.7
```

## Step 2: Observe the crash

The container exits almost immediately. Check the exit status:
```bash
docker inspect keeper --format='{{.State.ExitCode}}'
# Expected: non-zero (139 for SIGSEGV)
```

Check logs:
```bash
docker logs keeper 2>&1 | tail -20
```

The logs will show Keeper beginning initialization and then terminating with a segfault during snapshot install or log preprocessing.

## Step 3: Confirm it is reproducible

```bash
docker rm keeper
docker run --name keeper --network host \
  -v $(pwd)/keeper_config.xml:/etc/clickhouse-keeper/keeper_config.xml \
  clickhouse/clickhouse-keeper:22.7
# Same crash occurs
```

## Expected result (bug present)
The Keeper process crashes with signal 11 (SIGSEGV) during startup initialization.

## Expected result (bug absent)
The Keeper process starts successfully and listens on port 2181:
```bash
echo ruok | nc localhost 2181
# Returns: imok
```
