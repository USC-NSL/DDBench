#!/usr/bin/env bash
# Setup script for redpanda-25769-listoffsets-wrong (source build)
# Clones Redpanda, checks out the buggy commit, and builds from source.
# Build WORKS with -Wno-error on GCC 13.
# WARNING: Redpanda builds take 30-60 minutes depending on your hardware.
set -euo pipefail

CASE_NAME="redpanda-25769-listoffsets-wrong"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/${CASE_NAME}"
SOURCE_REPO="https://github.com/redpanda-data/redpanda.git"
SOURCE_COMMIT="18b0c24d7b306add4a1390fc2c56a5de5420f567~1"
REDPANDA_BIN="$WORK_DIR/bin/redpanda"
RPK_BIN="$WORK_DIR/bin/rpk"

export PATH="$PATH:/usr/local/go/bin"

echo "=== Setting up ${CASE_NAME} (source build) ==="
echo ""
echo "WARNING: Redpanda builds from source take 30-60 minutes."
echo "         Make sure you have at least 16 GB RAM and 30 GB disk space."
echo ""

# ── Install build dependencies ──
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake ninja-build git \
    libboost-all-dev ragel libhwloc-dev libnuma-dev \
    libsctp-dev libxml2-dev xfslibs-dev \
    systemtap-sdt-dev libtool libyaml-cpp-dev \
    libfmt-dev libprotobuf-dev protobuf-compiler \
    pkg-config python3 python3-jinja2 python3-jsonschema python3-pip \
    libsnappy-dev liblz4-dev libzstd-dev libxxhash-dev \
    libgnutls28-dev libcrypto++-dev golang-go

# Install Python test dependency
echo "Installing confluent-kafka Python library..."
pip3 install confluent-kafka 2>/dev/null || pip install confluent-kafka 2>/dev/null || {
    echo "WARNING: Failed to install confluent-kafka. The reproduce script needs it."
}

# Check prerequisites
for cmd in git cmake ninja g++; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Check Go availability
if ! command -v go &>/dev/null; then
    echo "ERROR: go is required but not installed. Install Go or ensure /usr/local/go/bin is in PATH."
    exit 1
fi

# Create directory structure
mkdir -p "$WORK_DIR"/{bin,conf,data,logs}

# ── Step 1: Clone and checkout source ──
if [ -d "$WORK_DIR/src/.git" ]; then
    echo "Source already cloned at $WORK_DIR/src — skipping clone."
else
    echo "Cloning Redpanda source..."
    git clone "$SOURCE_REPO" "$WORK_DIR/src"
    cd "$WORK_DIR/src"
    git checkout "$SOURCE_COMMIT"
    git submodule update --init --recursive
    echo "Source cloned and checked out to $WORK_DIR/src"
fi

# ── Step 2: Build redpanda (C++) from source ──
if [ -f "$REDPANDA_BIN" ]; then
    echo "Redpanda binary already available at $REDPANDA_BIN — skipping build."
else
    SRC_BIN="$WORK_DIR/src/build/release/src/v/redpanda/redpanda"
    if [ -f "$SRC_BIN" ]; then
        echo "Source build found. Copying binary..."
        cp "$SRC_BIN" "$REDPANDA_BIN"
        chmod +x "$REDPANDA_BIN"
    else
        echo ""
        echo "Building Redpanda from source (this will take 30-60 minutes)..."
        echo "Start time: $(date)"
        cd "$WORK_DIR/src"
        mkdir -p build/release && cd build/release
        cmake ../.. -GNinja -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_CXX_FLAGS="-Wno-error"
        ninja redpanda
        echo "Build complete at: $(date)"
        cp "$SRC_BIN" "$REDPANDA_BIN"
        chmod +x "$REDPANDA_BIN"
        echo "Redpanda binary at: $REDPANDA_BIN"
    fi
fi

# ── Step 3: Build rpk (Go) ──
if [ -f "$RPK_BIN" ]; then
    echo "rpk already available at $RPK_BIN — skipping."
else
    echo "Building rpk from source..."
    cd "$WORK_DIR/src/src/go/rpk"
    go build -o "$RPK_BIN" ./cmd/rpk
    chmod +x "$RPK_BIN"
    echo "rpk built at: $RPK_BIN"
fi

# ── Step 4: Create config file ──
cat > "$WORK_DIR/conf/redpanda.yaml" <<EOF
redpanda:
  data_directory: ${WORK_DIR}/data
  node_id: 0
  rpc_server:
    address: "0.0.0.0"
    port: 33145
  kafka_api:
    address: "0.0.0.0"
    port: 9092
  admin:
    address: "0.0.0.0"
    port: 9644
  developer_mode: true
pandaproxy:
  pandaproxy_api:
    address: "0.0.0.0"
    port: 8082
EOF

echo ""
echo "=== Setup complete ==="
echo ""
echo "Directory layout:"
echo "  Source code:  $WORK_DIR/src/"
echo "  Redpanda:    $REDPANDA_BIN"
echo "  rpk:         $RPK_BIN"
echo "  Config:      $WORK_DIR/conf/redpanda.yaml"
echo "  Data:        $WORK_DIR/data/"
echo ""
echo "To reproduce the bug:  ./reproduce.sh"
