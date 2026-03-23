#!/usr/bin/env bash
# Setup script for clickhouse-98079-keeper-addwatch
# Clones ClickHouse source, checks out the buggy commit, and builds Keeper from source.
# cmake/tools.cmake requires Clang 21 which doesn't exist as a package.
# We patch it to accept Clang 18 instead.
# WARNING: ClickHouse builds take 30-90 minutes depending on your hardware.
set -euo pipefail

CASE_NAME="clickhouse-98079-keeper-addwatch"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/${CASE_NAME}"
SOURCE_REPO="https://github.com/ClickHouse/ClickHouse.git"
SOURCE_COMMIT="3515972fbc064f7b62c963c8e25969053a6a38c2~1"
CLICKHOUSE_BIN="$WORK_DIR/src/build/programs/clickhouse-keeper"
ZK_VERSION="3.8.4"
ZK_URL="https://archive.apache.org/dist/zookeeper/zookeeper-${ZK_VERSION}/apache-zookeeper-${ZK_VERSION}-bin.tar.gz"

echo "=== Setting up ${CASE_NAME} ==="
echo ""
echo "WARNING: ClickHouse builds from source take 30-90 minutes."
echo "         Make sure you have at least 16 GB RAM and 30 GB disk space."
echo ""

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake ninja-build clang lld git

# Java is needed for zkCli.sh
if ! command -v java &>/dev/null; then
    echo "Installing Java for zkCli.sh..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y default-jre-headless
fi

# Check prerequisites
for cmd in git cmake ninja clang clang++; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Create directory structure
mkdir -p "$WORK_DIR"/{conf,data,logs,tools}

# ── Step 1: Clone and checkout source ──
if [ -d "$WORK_DIR/src/.git" ]; then
    echo "Source already cloned at $WORK_DIR/src — skipping clone."
else
    echo "Cloning ClickHouse source..."
    git clone --recurse-submodules "$SOURCE_REPO" "$WORK_DIR/src"
    cd "$WORK_DIR/src"
    git checkout "$SOURCE_COMMIT"
    git submodule update --init --recursive
    echo "Source cloned and checked out to $WORK_DIR/src"
fi

# ── Step 2: Build from source ──
if [ -f "$CLICKHOUSE_BIN" ]; then
    echo "Binary already built at $CLICKHOUSE_BIN — skipping build."
else
    echo ""
    echo "Building ClickHouse Keeper from source (this will take 30-90 minutes)..."
    echo "Start time: $(date)"
    cd "$WORK_DIR/src"

    # Patch cmake/tools.cmake to lower the minimum Clang version from 21 to 18
    # (Clang 21 doesn't exist as an apt package)
    sed -i 's/set (CLANG_MINIMUM_VERSION 21)/set (CLANG_MINIMUM_VERSION 18)/' cmake/tools.cmake

    mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Debug -DENABLE_TESTS=OFF -DENABLE_UTILS=OFF \
        -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang
    ninja clickhouse-keeper
    echo "Build complete at: $(date)"
    echo "Binary at: $CLICKHOUSE_BIN"
fi

# ── Step 3: Download Apache ZooKeeper for zkCli.sh ──
ZK_DIR="$WORK_DIR/tools/apache-zookeeper-${ZK_VERSION}-bin"
if [ -d "$ZK_DIR" ]; then
    echo "ZooKeeper already downloaded at $ZK_DIR — skipping."
else
    echo "Downloading Apache ZooKeeper ${ZK_VERSION} for zkCli.sh..."
    cd "$WORK_DIR/tools"
    curl -L -o "apache-zookeeper-${ZK_VERSION}-bin.tar.gz" "$ZK_URL"
    tar xzf "apache-zookeeper-${ZK_VERSION}-bin.tar.gz"
    rm -f "apache-zookeeper-${ZK_VERSION}-bin.tar.gz"
    echo "ZooKeeper extracted to $ZK_DIR"
fi

# ── Step 4: Create config files ──

# Keeper config
cat > "$WORK_DIR/conf/keeper_config.xml" <<EOF
<clickhouse>
    <keeper_server>
        <tcp_port>2181</tcp_port>
        <server_id>1</server_id>
        <log_storage_path>${WORK_DIR}/data/coordination/log</log_storage_path>
        <snapshot_storage_path>${WORK_DIR}/data/coordination/snapshots</snapshot_storage_path>
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
    <logger>
        <level>warning</level>
        <console>1</console>
    </logger>
</clickhouse>
EOF

echo ""
echo "=== Setup complete ==="
echo ""
echo "Directory layout:"
echo "  Source code:  $WORK_DIR/src/"
echo "  Binary:      $CLICKHOUSE_BIN"
echo "  zkCli.sh:    $ZK_DIR/bin/zkCli.sh"
echo "  Configs:     $WORK_DIR/conf/"
echo "  Data:        $WORK_DIR/data/"
echo ""
echo "To reproduce the bug:  ./reproduce.sh"
