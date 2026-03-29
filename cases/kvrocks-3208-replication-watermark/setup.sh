#!/usr/bin/env bash
# Setup script for kvrocks-3208-replication-watermark
# Clones the repository, checks out the buggy commit, and builds the project.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/kvrocks-3208-replication-watermark"
BUGGY_COMMIT="54929cd01603f9a19cd3b700b8b4da1683e4eda9~1"
REPO_URL="https://github.com/apache/kvrocks.git"

echo "=== Setting up kvrocks-3208-replication-watermark ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake git redis-tools

# Check prerequisites
for cmd in git cmake g++ redis-cli; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Clone
if [ ! -d "$WORK_DIR" ]; then
    echo "Cloning repository..."
    git clone --recurse-submodules "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Checkout buggy commit
echo "Checking out buggy commit..."
git checkout $BUGGY_COMMIT 2>/dev/null || git checkout $(git rev-parse $BUGGY_COMMIT)
git submodule update --init --recursive

# Build
if [ ! -f "$WORK_DIR/build/kvrocks" ]; then
    echo "Building (this may take several minutes)..."
    mkdir -p build && cd build
    cmake .. -DCMAKE_BUILD_TYPE=Debug
    make -j$(nproc)
else
    echo "Binary already exists, skipping build."
fi

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/build/kvrocks"
