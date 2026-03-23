#!/usr/bin/env bash
# Setup script for clickhouse-99109-sum-nondeterministic (pure source build)
# Clones ClickHouse, checks out the buggy version, and builds from source.
# WARNING: ClickHouse builds take 30-90 minutes depending on your hardware.
set -euo pipefail

CASE_NAME="clickhouse-99109-sum-nondeterministic"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/${CASE_NAME}"
SOURCE_REPO="https://github.com/ClickHouse/ClickHouse.git"
SOURCE_TAG="v24.12.1.1614-stable"

echo "=== Setting up ${CASE_NAME} (pure source build) ==="
echo ""
echo "WARNING: ClickHouse builds from source take 30-90 minutes."
echo "         Make sure you have at least 16 GB RAM and 30 GB disk space."
echo ""

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake ninja-build clang lld git

# Check prerequisites
for cmd in git cmake ninja; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Create directory structure
mkdir -p "$WORK_DIR"/{conf,data,logs}

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
CLICKHOUSE_BIN="$WORK_DIR/src/build/programs/clickhouse"
if [ -f "$CLICKHOUSE_BIN" ]; then
    echo "Binary already built at $CLICKHOUSE_BIN — skipping build."
else
    echo ""
    echo "Building ClickHouse from source (this will take 30-90 minutes)..."
    echo "Start time: $(date)"
    cd "$WORK_DIR/src"
    mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Debug -DENABLE_TESTS=OFF -DENABLE_UTILS=OFF
    ninja clickhouse-server clickhouse-client
    echo "Build complete at: $(date)"
    echo "Binary at: $CLICKHOUSE_BIN"
fi

# ── Step 3: Create config files ──

# Main server config (single instance, no cluster needed)
cat > "$WORK_DIR/conf/server.xml" <<EOF
<clickhouse>
    <logger>
        <level>warning</level>
        <console>1</console>
    </logger>
    <http_port>8123</http_port>
    <tcp_port>9000</tcp_port>
    <path>${WORK_DIR}/data/</path>
    <tmp_path>${WORK_DIR}/data/tmp/</tmp_path>
    <user_files_path>${WORK_DIR}/data/user_files/</user_files_path>
    <format_schema_path>${WORK_DIR}/data/format_schemas/</format_schema_path>
    <users_config>${WORK_DIR}/conf/users.xml</users_config>
    <default_profile>default</default_profile>
    <default_database>default</default_database>
    <listen_host>0.0.0.0</listen_host>
</clickhouse>
EOF

# Users config
cat > "$WORK_DIR/conf/users.xml" <<'EOF'
<clickhouse>
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
</clickhouse>
EOF

echo ""
echo "=== Setup complete ==="
echo ""
echo "Directory layout:"
echo "  Source code:  $WORK_DIR/src/"
echo "  Binary:      $WORK_DIR/src/build/programs/clickhouse"
echo "  Configs:     $WORK_DIR/conf/"
echo "  Data:        $WORK_DIR/data/"
echo ""
echo "To reproduce the bug:  ./reproduce.sh"
