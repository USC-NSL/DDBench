#!/usr/bin/env bash
# Setup script for dragonfly-6687-replica-rdb-encoding
# Clones the repository, checks out the buggy commit, and builds the project.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/dragonfly-6687-replica-rdb-encoding"
BUGGY_COMMIT="8347cd80192a7be967a3983a6a55a10525915015~1"
REPO_URL="https://github.com/dragonflydb/dragonfly.git"

echo "=== Setting up dragonfly-6687-replica-rdb-encoding ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake ninja-build git

# Check prerequisites
for cmd in git cmake ninja g++; do
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

# Build (Release build required for this case)
# Note: blaze.sh always creates a build-dbg directory regardless of CMAKE_BUILD_TYPE.
# We symlink build-opt -> build-dbg so the reproduce script can find the binary.
if [ ! -f "$WORK_DIR/build-opt/dragonfly" ]; then
    echo "Building Release (this may take several minutes)..."
    ./helio/blaze.sh -DCMAKE_BUILD_TYPE=Release -DWITH_AWS=OFF
    cd build-dbg && ninja dragonfly
    cd "$WORK_DIR"
    [ ! -e build-opt ] && ln -s build-dbg build-opt
else
    echo "Binary already exists, skipping build."
fi

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/build-opt/dragonfly"
