#!/usr/bin/env bash
# Setup script for clickhouse-29332-predicate-pushdown
# Clones ClickHouse source, checks out the buggy version, and builds from source.
# This version (v21.10) supports GCC 13 and requires disabling some optional features.
# WARNING: ClickHouse builds take 30-90 minutes depending on your hardware.
set -euo pipefail

CASE_NAME="clickhouse-29332-predicate-pushdown"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/${CASE_NAME}"
SOURCE_REPO="https://github.com/ClickHouse/ClickHouse.git"
SOURCE_TAG="v21.10.1.8013-stable"
CLICKHOUSE_BIN="$WORK_DIR/src/build/programs/clickhouse"

echo "=== Setting up ${CASE_NAME} ==="
echo ""
echo "WARNING: ClickHouse builds from source take 30-90 minutes."
echo "         Make sure you have at least 16 GB RAM and 30 GB disk space."
echo ""

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake ninja-build git

# Check prerequisites
for cmd in git cmake ninja g++; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Create directory structure
mkdir -p "$WORK_DIR"/{conf,data/shard1,data/shard2,logs}

# ── Step 1: Clone and checkout source ──
if [ -d "$WORK_DIR/src/.git" ]; then
    echo "Source already cloned at $WORK_DIR/src — skipping clone."
else
    echo "Cloning ClickHouse source at ${SOURCE_TAG}..."
    git clone --recurse-submodules "$SOURCE_REPO" "$WORK_DIR/src"
    cd "$WORK_DIR/src"
    git checkout "$SOURCE_TAG"
    git submodule update --init --recursive
    echo "Source cloned to $WORK_DIR/src"
fi

# ── Step 2: Build from source ──
if [ -f "$CLICKHOUSE_BIN" ]; then
    echo "Binary already built at $CLICKHOUSE_BIN — skipping build."
else
    echo ""
    echo "Building ClickHouse from source (this will take 30-90 minutes)..."
    echo "Start time: $(date)"
    cd "$WORK_DIR/src"
    mkdir -p build && cd build
    # Old v21.10 has broken optional submodules (contrib/icu, contrib/nanodbc).
    # Disable optional features to avoid build failures.
    cmake .. -DCMAKE_BUILD_TYPE=Debug \
        -DENABLE_TESTS=OFF -DENABLE_UTILS=OFF \
        -DENABLE_ICU=OFF -DENABLE_NLP=OFF \
        -DENABLE_ODBC=OFF -DENABLE_EMBEDDED_COMPILER=OFF
    ninja clickhouse-server clickhouse-client
    echo "Build complete at: $(date)"
    echo "Binary at: $CLICKHOUSE_BIN"
fi

# ── Step 3: Create config files ──

# Main server config for shard 1 (v21.10 uses <yandex> root)
cat > "$WORK_DIR/conf/server-shard1.xml" <<EOF
<yandex>
    <logger>
        <level>warning</level>
        <console>1</console>
    </logger>
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    <interserver_http_port>9009</interserver_http_port>
    <path>${WORK_DIR}/data/shard1/</path>
    <tmp_path>${WORK_DIR}/data/shard1/tmp/</tmp_path>
    <user_files_path>${WORK_DIR}/data/shard1/user_files/</user_files_path>
    <format_schema_path>${WORK_DIR}/data/shard1/format_schemas/</format_schema_path>
    <users_config>${WORK_DIR}/conf/users.xml</users_config>
    <default_profile>default</default_profile>
    <default_database>default</default_database>
    <listen_host>0.0.0.0</listen_host>
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
EOF

# Main server config for shard 2
cat > "$WORK_DIR/conf/server-shard2.xml" <<EOF
<yandex>
    <logger>
        <level>warning</level>
        <console>1</console>
    </logger>
    <http_port>8124</http_port>
    <tcp_port>9001</tcp_port>
    <interserver_http_port>9010</interserver_http_port>
    <path>${WORK_DIR}/data/shard2/</path>
    <tmp_path>${WORK_DIR}/data/shard2/tmp/</tmp_path>
    <user_files_path>${WORK_DIR}/data/shard2/user_files/</user_files_path>
    <format_schema_path>${WORK_DIR}/data/shard2/format_schemas/</format_schema_path>
    <users_config>${WORK_DIR}/conf/users.xml</users_config>
    <default_profile>default</default_profile>
    <default_database>default</default_database>
    <listen_host>0.0.0.0</listen_host>
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
EOF

# Users config (v21.10 uses <yandex> root)
cat > "$WORK_DIR/conf/users.xml" <<'EOF'
<yandex>
    <profiles>
        <default>
            <max_memory_usage>10000000000</max_memory_usage>
        </default>
    </profiles>
    <users>
        <default>
            <password></password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
            <access_management>1</access_management>
        </default>
    </users>
    <quotas>
        <default>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</yandex>
EOF

echo ""
echo "=== Setup complete ==="
echo ""
echo "Directory layout:"
echo "  Source code:  $WORK_DIR/src/"
echo "  Binary:      $CLICKHOUSE_BIN"
echo "  Configs:     $WORK_DIR/conf/"
echo "  Data:        $WORK_DIR/data/"
echo ""
echo "To reproduce the bug:  ./reproduce.sh"
